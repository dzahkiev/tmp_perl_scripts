#!/usr/bin/env perl
use common::sense;
BEGIN {
	$ENV{DEV}++ if qx(pwd) =~ /dev/;
	use if qx(pwd) =~ /dev/, lib => qw(lib /tk/lib);
	use if qx(pwd) !~ /dev/, lib => qw(/tk/mojo/lib lib /tk/lib local/lib/perl5);
}

use utf8;
use Spreadsheet::WriteExcel::Simple;
use Util;

my $conf = do 'conf/app.conf';
my $DB   = Util->db( do 'conf/mysql.conf' );


for my $request (qw(867 878 873)) {
	my $rr = $DB->select("
		select 
			c.name country,
			city.name city,
			cinema.title cinema,
			h.title hall,
			h.crt_id h_crt,
			h.server_serial h_server_serial,
			crt.server_model crt_server_model,
			crt.server_sn_origin crt_server_sn_origin,
			timestampadd(hour,-rr.time_zone,rr.valid_since) vs, 
			timestampadd(hour,-rr.time_zone+4,rr.valid_since) vs_msk, 
			timestampadd(hour,-rr.time_zone,rr.valid_till) vt,
			timestampadd(hour,4-rr.time_zone,rr.valid_till) vt_msk,
			rr.sended sended
		from request_record rr
		left join hall h on rr.hall_id = h.id
		left join cinema on h.cinema_id = cinema.id
		left join crt on h.crt_id = crt.id
		left join city on cinema.city_id = city.id 
		left join region r on city.region_id  = r.id 
		left join country c on r.country_id = c.id
		where request_id=? and kdm_status not in ('uploaded','deleted') order by vs, vt, country, city, cinema, hall",
		$request
	);

	my $fname = join '/', $conf->{path}->{tmp}, "${request}__request_records.xls";

	if (gen_xls($rr, $fname)) {
		say "generated file: $fname";
	}
}


sub gen_xls {
	my $data = shift;
	my $filename = shift; 

	my $header =  [
		"#",
		"Страна",
		"Город",
		"Кинотеатр",
		"Номер зала",
		"Дата начала",
		"Дата окончания",
		"Номер сервера",
		"Дата отправки",
	];

	my $ss = Spreadsheet::WriteExcel::Simple->new;
	$ss->write_bold_row($header);

	my $num;
	for my $row ( @$data ) {

		$ss->write_row([
				++$num,
				$row->{country} || '',
				$row->{city}    || '',
				$row->{cinema}  || '',
				$row->{hall}    || '',
				sprintf("MSK: %s\n UTC: %s", Util::iso2human($row->{vs_msk}), Util::iso2human($row->{vs})),
				sprintf("MSK: %s\n UTC: %s", Util::iso2human($row->{vt_msk}), Util::iso2human($row->{vt})),
				(
					$row->{h_crt} 
					? join(' ', $row->{crt_server_model}, $row->{crt_server_sn_origin})
					: $row->{h_server_serial}
				),
				Util::iso2human($row->{sended}) || '',
		]);
	}

	$ss->save($filename);
}


