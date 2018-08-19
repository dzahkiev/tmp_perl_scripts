#!/usr/bin/env perl
BEGIN {
	$ENV{DEV}++ if qx(pwd) =~ /dev/;
	use if qx(pwd) =~ /dev/, lib => qw(lib /tk/lib);
	use if qx(pwd) !~ /dev/, lib => qw(/tk/mojo/lib lib /tk/lib local/lib/perl5);
}

use MojoX::Loader;
use Spreadsheet::WriteExcel;
use Spreadsheet::XLSX;
use Encode;
use Data::Dumper;
use Util;
use Mojo::ByteStream qw(html_unescape);

my $self = MojoX::Loader->load;
my $conf = $self->app->conf;
my $DB   = $self->app->db;

die "Usage: carton exec script/temporary/update_fond_kino.pl tmp/<your_file_name.xlsx>"
	unless my $filename = $ARGV[0];

my $wb = Spreadsheet::XLSX->new($filename);
my $write_wb  = Spreadsheet::WriteExcel->new('tmp/cinemas_by_city_region_in_copicus_db.xls');
my $write_ws  = $write_wb->add_worksheet();
my $write_wb2 = Spreadsheet::WriteExcel->new('tmp/cinemas_added_to_copicus_db.xls');
my $write_ws2 = $write_wb2->add_worksheet();
my $not_found_region;

my $col_number = {
	1  => 'region',
	3  => 'city',
	4  => 'cinema',
	5  => 'address',
	7  => 'dd24_status',
	9  => 'contacts',
	10 => 'email',
	11 => 'comment',
	#2 => 'type_place',
	#6 => 'cinema_type',
	#8 => 'audience',
};

my $city_added = {};
my $cnt = 1;

for my $worksheet ( $wb->worksheets() ) {
		my ($col_min,   $col_max) = $worksheet->col_range();
		my ($row_start, $row_end) = $worksheet->row_range();
		my ($row_curr, $row_curr2);

		for my $row ($row_start+1 .. $row_end) {
			my ($line, $data);

			for my $col ($col_min .. $col_max) {
				my $val = $worksheet->get_cell($row, $col) ? $self->trim($worksheet->get_cell($row, $col)->value()) : '';
				$val =~ s/(\,|\;)$//g if $col_number->{$col} eq 'city';
				$data->{ $col_number->{$col} } = $val if $col_number->{$col};
				push @$line, Encode::decode_utf8(b($val)->html_unescape);
			}

			my $region_id = $DB->select('select * from region where trim(name)=?', $self->trim($data->{region} || ''))->[0]->{id};

			unless ($region_id) {
				$region_id = $DB->select('select * from region where trim(name)=?', $self->trim(parse_region_name($data->{region} || '')))->[0]->{id};
			}
			my $city_id = $DB->select('select * from city where trim(name)=? and region_id=?', $self->trim($data->{city} || ''), $region_id)->[0]->{id};
			unless ($city_id) {
				$city_id = $DB->select("select * from city where (trim(name) regexp '" . $self->trim(parse_city_name($data->{city} || ''))
					. "[[.space.]]*[[.left-parenthesis.]].*[[.right-parenthesis.]]' or trim(name)=?) and region_id=?",
					$self->trim(parse_city_name($data->{city} || '')),
					$region_id
				)->[0]->{id};
			}
			my $cinema_id = $DB->select('select * from cinema where trim(title)=? and city_id=?',  $self->trim($data->{cinema} || ''), $city_id)->[0]->{id};
			
			unless ($region_id) {
				$not_found_region->{$data->{region}}++;
				$write_ws->write($row_curr++, 0, $line);
				next;
			}

			my $dd24status_id = {
				'dvd' => 28,
				'dcp' => 35,
			}->{ lc $self->trim($data->{dd24_status}) } || 0;

			if ((!$city_id || $city_added->{$city_id}) && $dd24status_id && !$cinema_id ) {
				# города с таким регионом нет в нашей базе
				# создаем кинотеатh (если его еще нет) и формируем xls внесенных в базу
				my $city_last_insertid;
				unless ($city_added->{$city_id}) {
					$DB->query('insert into city set name=?, name_en=?, population="5", region_id=?, added_by_system="1", created=now()',
						parse_city_name($data->{city} || ''),
						Util::win2translit(parse_city_name($data->{city} || '')),
						$region_id,
					);
					$city_last_insertid = $DB->{mysql_insertid};
				} else {
					$city_last_insertid = $city_id;
				}

				$city_added->{ $city_last_insertid }++;
				$DB->query('insert into cinema set title=?, title_en=?, city_id=?, dd24status_id=?, fond_kino=1, added_by_system=1, created=now()',
					$data->{cinema},
					Util::win2translit($data->{cinema}),
					$city_last_insertid,
					$dd24status_id,
				);

				my $cinema_id = $DB->{mysql_insertid};
				$DB->query('insert into cinema_contact set first_name=".", last_name=".", comment=?, cinema_id=?, created=now()',
					(join '; ', grep { $_ } map { $data->{$_} =~ s/&lt;/</ig; $data->{$_} =~ s/&gt;/>/ig; $data->{$_} } qw(address contacts email)),
					$cinema_id
				);
				$write_ws2->write($row_curr2++, 0, $line);
			} else {
				$write_ws->write($row_curr++, 0, $line);
			}
		}

		warn "Not found region: " . Dumper $not_found_region;
		$write_wb->close()  or die "Error closing file: $!";
		$write_wb2->close() or die "Error closing file: $!";

}



$self->mailsend(
	mail => { 
		from    => $conf->{sendmail}->{from},
		type    => 'text/html',
		data    => 'Добрый день! <br> Ниже прикреплены файлы exel:
		<br>1. ДИСИПИ 24 База участников ночи кино.xlsx -- <i>исходный файл</i>
		<br>2. cinemas_by_city_region_found_in_copicus_db.xls -- <i>список кинотеатров, по которым найдены города в базе Copicus и которые нужно сверить/вносить в базу вручную</i>
		<br>3. cinemas_added_to_copicus_db.xls -- <i>кинотеатры из этого списка добавлены в базу Copicus автоматически</i>',
		subject => 'Партнеры Фонда Кино',
		to      => [ $conf->{dev_mail} ],
		cc      => 'agibalov@tochkak.ru',
	},
	attach    => [
		{
			Filename    => 'ДИСИПИ 24 База участников ночи кино.xlsx',
			Disposition => 'attachment',
			Type        => 'application/excel',
			Path        => $filename,
		},
		{
			Filename    => 'cinemas_by_city_region_in_copicus_db.xls',
			Disposition => 'attachment',
			Type        => 'application/excel',
			Path        => 'tmp/cinemas_by_city_region_in_copicus_db.xls',
		},
		{
			Filename    => 'cinemas_added_to_copicus_db.xls',
			Disposition => 'attachment',
			Type        => 'application/excel',
			Path        => 'tmp/cinemas_added_to_copicus_db.xls',
		},
	],
	splitmail => 0,
);


sub parse_region_name {
	my $str = shift;

	if ($str =~ /Республика/i) {
		$str =~ s/(.*)(Республика)/$2 $1/i;
		$str =~ s/^\s+//;
		$str =~ s/\s+$//;
		$str =~ s/\s+/ /;
	}

	return $str;
}


sub parse_city_name {
	my $str = shift;
	my $str_old = $str;

	$str =~ s/(\s*\(.*\))//ig;
	$str =~ s/(ЗАТО\s*)//ig;
	$str =~ s/^((п|с|д|г)\.\s*)//g;
	$str =~ s/^\s+//;
	$str =~ s/\s+$//;
	$str =~ s/\s+/ /;
	unless ($str_old eq $str) {
		warn "$str_old ==> $str";
	}

	$str;
}
