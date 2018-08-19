#!/usr/bin/env perl
BEGIN {
	$ENV{DEV}++ if qx(pwd) =~ /dev/;
	use if qx(pwd) =~ /dev/, lib => qw(lib /tk/lib);
	use if qx(pwd) !~ /dev/, lib => qw(/tk/mojo/lib lib /tk/lib);
}

use common::sense;
use Shipment::DHL;
use File::Spec;
use utf8;
use Mojo::Log;
my $log = Mojo::Log->new(path => 'log/shipper_status.log', level => 'info');

my $DB = Util->db(require 'conf/mysql.conf');
my $conf = do 'conf/app.conf';

use Mojo::Run;
my $r = Mojo::Run->new;

my $shipper = {
	cse => 361,
	dhl => 353,
};

my $period = $ENV{DEV} ? 10 : (20 * 60);

$r->ioloop->recurring( $period => sub {
	eval {
		for my $name (keys %$shipper) {
			my $shipment = $DB->select('
				select barcode, request_id
				from
					shipment
				where
					shipper_id=?
					and status="delivered"
					and barcode!="" and barcode is not null
					and datediff(now(), updated) > 10
					and datediff(now(), updated) < 45
				order by rand() limit 1',
				$shipper->{$name}
			)->[0];

			next unless $shipment;

			if (lc $name eq 'dhl') {
				my $ship = Shipment::DHL->new(
					'site_id'  => $conf->{shipment}->{dhl}->{site_id},
					'password' => $conf->{shipment}->{dhl}->{password}
				);

				my $check = {
					tracking => sub { $ship->tracking({ 'AWB' => [ $shipment->{barcode} ] }) },
					print    => sub { $ship->get_pdf({ 'RequestId' => $shipment->{request_id} }) }
				};

				my $status_info;
				for (qw(tracking print)) {
					my $res = $check->{$_}();

					my $status = $ship->http_status();
					if ($res->{error}) {
						$status = '403' if $status eq '200';
						$status_info .= ($status_info ? '<br>' : '') . $res->{error};
					}

					update_shipper_status({
						($_ eq 'tracking' ? 'tracking_status' : 'http_status') => $status,
						status_info => $status_info,
						shipper_id  => $shipper->{$name}
					});
				}
			}

			my $path = File::Spec->catfile($conf->{path}->{shipment}, "${name}_tmp_waybill.pdf");
			if (-e -f $path) {
				unlink $path;
				$log->info("Removed file: $path");
			}
		}
	};
	$log->warn($@) if $@;
});

$r->ioloop->start;


sub update_shipper_status {
	my $data = shift || return;

	return unless $data->{shipper_id};

	my $status = $data->{tracking_status} ? 'tracking_status' : 'http_status';

	$DB->query("update shipper set $status=?, status_info=? where id=?",
		$data->{$status}     || '200',
		$data->{status_info} || '',
		$data->{shipper_id}
	);

	$log->info(sprintf(
		"Shipper ID: %s; $status: %s; Status_info: %s",
		$data->{shipper_id},
		$data->{$status}     || 200,
		$data->{status_info} || '-',
	));

}
