#!/usr/bin/perl

use strict;
use warnings;

my $href_RISumUsageAndCost = {};

while (<>) {
  chomp;

  # NOTE: for US-East, it's just HeavyUsage
  my $f_ProductCode = 'AmazonEC2';
  my $f_UsageType   = 'APS1-HeavyUsage';
  if ( $_ =~ /Smart.+${f_ProductCode}.+${f_UsageType}.+hourly fee/ ) {

    my $ProductCode     = _extract_data( $_, 12 );    # ProductCode
    my $UsageType       = _extract_data( $_, 15 );    # UsageType
    my $ItemDescription = _extract_data( $_, 19 );    # ItemDescription
    my $UsageQuantity   = _extract_data( $_, 22 );    # UsageQuantity
    my $TotalCost       = _extract_data( $_, 29 );    # TotalCost

    my $cur_SumUsageQuantity =
      exists( $href_RISumUsageAndCost->{$ProductCode}->{$UsageType}
        ->{'SumUsageQuantity'} )
      ? $href_RISumUsageAndCost->{$ProductCode}->{$UsageType}
      ->{'SumUsageQuantity'}
      : 0;
    $href_RISumUsageAndCost->{$ProductCode}->{$UsageType}->{'SumUsageQuantity'}
      = $cur_SumUsageQuantity + $UsageQuantity;

    my $cur_SumTotalCost =
      exists(
      $href_RISumUsageAndCost->{$ProductCode}->{$UsageType}->{'SumTotalCost'} )
      ? $href_RISumUsageAndCost->{$ProductCode}->{$UsageType}->{'SumTotalCost'}
      : 0;
    $href_RISumUsageAndCost->{$ProductCode}->{$UsageType}->{'SumTotalCost'} =
      $cur_SumTotalCost + $TotalCost;

    # print $UsageType . "\n";
  }

}

print 'done';

sub _extract_data {
  my ( $d, $i ) = @_;
  my $type = undef;

  # get the instance type string
  my @a = split( /","/, $d );

  # (undef, $type) = split(/:/, $a[15]);
  $type = $a[$i];

  if ( not $type ) { die }

  return $type;
}
