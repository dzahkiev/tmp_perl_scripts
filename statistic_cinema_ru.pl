#!/usr/bin/env perl

BEGIN {
	$ENV{DEV}++ if qx(pwd) =~ /dev/;
	use if qx(pwd) =~ /dev/, lib => qw(lib /tk/lib);
	use if qx(pwd) !~ /dev/, lib => qw(/tk/mojo/lib lib /tk/lib);
}

use Util;
use utf8;
use Spreadsheet::WriteExcel::Simple;
my $DB   = Util->db(do 'conf/mysql.conf');
my $conf = do 'conf/app.conf';

my $top_12 = [
	'Каро Фильм', 'ОАО Киномакс', 'Люксор', 'Мираж Синема',
	'Монитор', 'Мори Синема', 'Премьер Зал', 'Пять Звезд Синема',
	'ООО "Синема 5"', 'Синема Парк', 'Синема стар', 'Формула Кино'
];

my $top12_ids = [ map { $_->{id} } @{$DB->select('select * from cinema_network where name' . $DB->in(@$top_12)) || []} ];

my $condition_cinema = "c.status='works'
	and (c.added_by_system is null or c.added_by_system=0)
	and lower(c.title) not REGEXP '[[:<:]]тест|тестовый|демо[[:>:]]'";
my $condition_hall   = "
	!h.non_commercial     and
	!h.inoperative        and
	h.history_of is null  and
	!h.need_moderate      and
	h.archived is null    and
	h.p_digital='yes'";

my $cinema = {};
$cinema->{top12} = $DB->select(
	"select
		h.id hall, h.capasity capasity, c.id cinema from hall h
	join cinema c on h.cinema_id = c.id
	join cinema_network cn on c.cinema_network_id = cn.id
	join city on c.city_id = city.id
	join region r on city.region_id = r.id
	join country con on r.country_id = con.id
	where
		$condition_cinema and $condition_hall
		and con.id=3159
		and c.cinema_network_id" . $DB->in(@$top12_ids)
);

$cinema->{except_top12} = $DB->select(
	"select
		h.id hall, h.capasity capasity, c.id cinema from hall h
	join cinema c on h.cinema_id = c.id
	join cinema_network cn on c.cinema_network_id = cn.id
	join city on c.city_id = city.id
	join region r on city.region_id = r.id
	join country con on r.country_id = con.id
	where
		$condition_cinema and $condition_hall
		and con.id=3159
		and c.cinema_network_id is not null
		and c.cinema_network_id!=0 
		and c.cinema_network_id not" . $DB->in(@$top12_ids)
);

$cinema->{other} = $DB->select(grep {warn $_}
	"select
		h.id hall, h.capasity capasity, c.id cinema from hall h
	join cinema c on h.cinema_id = c.id
	left join cinema_network on c.cinema_network_id = cinema_network.id
	join city on c.city_id = city.id
	join region r on city.region_id = r.id
	join country con on r.country_id = con.id
	where
		$condition_cinema and $condition_hall
		and con.id=3159
		and cinema_network.name is null"
);


my $data = {};
my $stat = {};

for my $group (keys %$cinema) {
	for (@{$cinema->{$group}}) {
		$data->{$group}->{$_->{cinema}}->{$_->{hall}}->{capasity} += $_->{capasity};
	}

	for my $c (keys %{$data->{$group}}) {
		next unless $c;
		$stat->{$group}->{cnt_cinema}++;
		for (keys %{$data->{$group}->{$c}}) {
			$stat->{$group}->{cnt_hall}++;
			$stat->{$group}->{capasity} += $data->{$group}->{$c}->{$_}->{capasity};
		}
	}

	for my $c (keys %{$data->{$group}}) {
		next unless $c > 0;
		if (scalar keys %{$data->{$group}->{$c}} <= 7) {
			$stat->{$group}->{cnt_cinema_1_7}++;
			for (keys %{$data->{$group}->{$c}}) {
				$stat->{$group}->{cnt_hall_1_7}++;
				$stat->{$group}->{capasity_1_7} += $data->{$group}->{$c}->{$_}->{capasity};
			}
		} elsif (scalar keys %{$data->{$group}->{$c}} <= 15) {
			$stat->{$group}->{cnt_cinema_8_15}++;
			for (keys %{$data->{$group}->{$c}}) {
				$stat->{$group}->{cnt_hall_8_15}++;
				$stat->{$group}->{capasity_8_15} += $data->{$group}->{$c}->{$_}->{capasity};
			}
		} elsif (scalar keys %{$data->{$group}->{$c}} > 15) {
			$stat->{$group}->{cnt_cinema_16}++;
			for (keys %{$data->{$group}->{$c}}) {
				$stat->{$group}->{cnt_hall_16}++;
				$stat->{$group}->{capasity_16} += $data->{$group}->{$c}->{$_}->{capasity};
			}
		}
	}
}


my $path = join '/', $conf->{path}->{tmp}, 'statistic_cinema_halls_ru.xls';
my $ss = Spreadsheet::WriteExcel::Simple->new;

my $title = {
	top12        => 'ТОП 12 (Россия)',
	except_top12 => 'Остальные сети (Россия)',
	other        => 'Независимые кинотеатры (Россия)',
};

for my $group (qw /top12 except_top12 other/) {
	$ss->write_bold_row(["$title->{$group} (по всем)"]);
	$ss->write_bold_row(['Количество кинотеатров', 'Количество залов', 'Количество мест']);
	$ss->write_row([($stat->{$group}->{cnt_cinema} || 0), ($stat->{$group}->{cnt_hall} || 0), ($stat->{$group}->{capasity} || 0)]);

	$ss->write_bold_row(["$title->{$group} (1-7 залов)"]);
	$ss->write_bold_row(['Количество кинотеатров', 'Количество залов', 'Количество мест']);
	$ss->write_row([($stat->{$group}->{cnt_cinema_1_7} || 0), ($stat->{$group}->{cnt_hall_1_7} || 0), ($stat->{$group}->{capasity_1_7} || 0)]);

	$ss->write_bold_row(["$title->{$group} (8-15 залов)"]);
	$ss->write_bold_row(['Количество кинотеатров', 'Количество залов', 'Количество мест']);
	$ss->write_row([($stat->{$group}->{cnt_cinema_8_15} || 0), ($stat->{$group}->{cnt_hall_8_15} || 0), ($stat->{$group}->{capasity_8_15} || 0)]);

	$ss->write_bold_row(["$title->{$group} (16+ залов)"]);
	$ss->write_bold_row(['Количество кинотеатров', 'Количество залов', 'Количество мест']);
	$ss->write_row([($stat->{$group}->{cnt_cinema_16} || 0), ($stat->{$group}->{cnt_hall_16} || 0), ($stat->{$group}->{capasity_16} || 0)]);
}

print "generated file: $path" if $ss->save($path);










