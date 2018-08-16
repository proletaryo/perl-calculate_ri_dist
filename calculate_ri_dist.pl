#!/usr/bin/perl

use strict;
use warnings;

my $href_Data = {};

while (<>) {
  chomp;

  # NOTE: for US-East, it's just HeavyUsage
  my $f_ProductCode = 'AmazonEC2';
  my $f_UsageType   = 'APS1-HeavyUsage';

  my $LinkedAccountId   = _extract_data( $_, 2 );     # LinkedAccountId
  my $LinkedAccountName = _extract_data( $_, 9 );     # LinkedAccountName
  my $ProductCode       = _extract_data( $_, 12 );    # ProductCode
  my $UsageType         = _extract_data( $_, 15 );    # UsageType
  my $UsageQuantity     = _extract_data( $_, 22 );    # UsageQuantity
  my $TotalCost         = _extract_data( $_, 29 );    # TotalCost
  my $CostCodeCategory  = _extract_data( $_, 32 );    # CostCodeCategory

  # Get all RIs
  if ( $_ =~ /Smart.+${f_ProductCode}.+${f_UsageType}.+hourly fee/ ) {

    my ( $RegionUsageType, undef ) = split( /:/, $UsageType );
    my $RIPurchasedType = _get_RI_purchased_type($_);

    my $cur_SumUsageQuantity =
      exists( $href_Data->{'HeavyUsage'}->{$ProductCode}->{$RegionUsageType}
        ->{$RIPurchasedType}->{'SumUsageQuantity'} )
      ? $href_Data->{'HeavyUsage'}->{$ProductCode}->{$RegionUsageType}
      ->{$RIPurchasedType}->{'SumUsageQuantity'}
      : 0;
    $href_Data->{'HeavyUsage'}->{$ProductCode}->{$RegionUsageType}
      ->{$RIPurchasedType}->{'SumUsageQuantity'} =
      $cur_SumUsageQuantity + $UsageQuantity;

    my $cur_SumTotalCost =
      exists( $href_Data->{'HeavyUsage'}->{$ProductCode}->{$RegionUsageType}
        ->{$RIPurchasedType}->{'SumTotalCost'} )
      ? $href_Data->{'HeavyUsage'}->{$ProductCode}->{$RegionUsageType}
      ->{$RIPurchasedType}->{'SumTotalCost'}
      : 0;
    $href_Data->{'HeavyUsage'}->{$ProductCode}->{$RegionUsageType}
      ->{$RIPurchasedType}->{'SumTotalCost'} = $cur_SumTotalCost + $TotalCost;
  }

  # Get all usage that consumed RIs
  elsif ( $_ =~ /${f_ProductCode}.+BoxUsage.+reserved instance applied/ ) {

    my ( $RegionUsageType, undef ) = split( /:/, $UsageType );
    my $RIAppliedType = _get_RI_applied_type($_);

    $href_Data->{'BoxUsage'}->{$ProductCode}->{$RegionUsageType}
      ->{$RIAppliedType}->{$LinkedAccountId}->{'CostCodeCategory'} =
      $CostCodeCategory;
    $href_Data->{'BoxUsage'}->{$ProductCode}->{$RegionUsageType}
      ->{$RIAppliedType}->{$LinkedAccountId}->{'LinkedAccountName'} =
      $LinkedAccountName;

    my $cur_UsageQuantity =
      exists( $href_Data->{'BoxUsage'}->{$ProductCode}->{$RegionUsageType}
        ->{$RIAppliedType}->{$LinkedAccountId}->{'UsageQuantity'} )
      ? $href_Data->{'BoxUsage'}->{$ProductCode}->{$RegionUsageType}
      ->{$RIAppliedType}->{$LinkedAccountId}->{'UsageQuantity'}
      : 0;
    $href_Data->{'BoxUsage'}->{$ProductCode}->{$RegionUsageType}
      ->{$RIAppliedType}->{$LinkedAccountId}->{'UsageQuantity'} =
      $cur_UsageQuantity + $UsageQuantity;

    # calculate the total UsageQuantity per InstanceType
    my $cur_SumUsageQuantity =
      exists( $href_Data->{'RawUsage'}->{$ProductCode}->{$RegionUsageType}
        ->{$RIAppliedType}->{'SumUsageQuantity'} )
      ? $href_Data->{'RawUsage'}->{$ProductCode}->{$RegionUsageType}
      ->{$RIAppliedType}->{'SumUsageQuantity'}
      : 0;
    $href_Data->{'RawUsage'}->{$ProductCode}->{$RegionUsageType}
      ->{$RIAppliedType}->{'SumUsageQuantity'} =
      $cur_SumUsageQuantity + $UsageQuantity;
  }
}

# calculate cost distribution
# href->RawUsage->APS1->InstanceType->DistUsageQuantity->LinkAccountId:CostCodeCategory
if ( exists( $href_Data->{'BoxUsage'}->{'APS1-BoxUsage'} ) ) {
  for my $k0 ( keys %{ $href_Data->{'BoxUsage'}->{'APS1-BoxUsage'} } )
  {    # InstanceType
    for my $k1 ( keys %{ $href_Data->{'BoxUsage'}->{'APS1-BoxUsage'}->{$k0} } )
    {    # LinkedAccountId
    }
  }
}

# href->RICostDistribution->APS1->AmazonEC2->LinkAccountId->CostCodeCategory
# href->RICostDistribution->APS1->AmazonEC2->LinkAccountId->DistributedCost

print 'done';

sub _extract_data {
  my ( $d, $i ) = @_;
  my $type = undef;

  # get the instance type string
  my @a = split( /","/, $d );

  $type = $a[$i];

  return $type;
}

sub _get_RI_applied_type {
  my $d     = shift @_;
  my $value = undef;

  my $ItemDescription = _extract_data( $d, 19 );
  if ( $ItemDescription =~ /, (.+) reserved instance applied/ ) {
    $value = $1;
  }

  return $value;
}

sub _get_RI_purchased_type {
  my $d     = shift @_;
  my $value = undef;

  my $ItemDescription = _extract_data( $d, 19 );
  if ( $ItemDescription =~ /, (.+) instance/ ) {
    $value = $1;
  }

  return $value;
}
