#!/usr/bin/perl

use strict;
use warnings;

my $href_Data = {};

# TODO:
# - handle both RDS and EC2
# - distinction between different OS types

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
  if ( $_ =~ /Smart.+${f_ProductCode}.+HeavyUsage.+hourly fee/ ) {

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

    my $key =
      join( ':', $LinkedAccountId, $LinkedAccountName, $CostCodeCategory );

    $href_Data->{'BoxUsage'}->{$ProductCode}->{$RegionUsageType}
      ->{$RIAppliedType}->{$key}->{'LinkedAccountId'} = $LinkedAccountId;
    $href_Data->{'BoxUsage'}->{$ProductCode}->{$RegionUsageType}
      ->{$RIAppliedType}->{$key}->{'LinkedAccountName'} = $LinkedAccountName;
    $href_Data->{'BoxUsage'}->{$ProductCode}->{$RegionUsageType}
      ->{$RIAppliedType}->{$key}->{'CostCodeCategory'} = $CostCodeCategory;

    my $cur_UsageQuantity =
      exists( $href_Data->{'BoxUsage'}->{$ProductCode}->{$RegionUsageType}
        ->{$RIAppliedType}->{$key}->{'UsageQuantity'} )
      ? $href_Data->{'BoxUsage'}->{$ProductCode}->{$RegionUsageType}
      ->{$RIAppliedType}->{$key}->{'UsageQuantity'}
      : 0;
    $href_Data->{'BoxUsage'}->{$ProductCode}->{$RegionUsageType}
      ->{$RIAppliedType}->{$key}->{'UsageQuantity'} =
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

my $href_EC2RICostSummary = _calculateRICostSummary($href_Data);
print 'done';

# sub functions
sub _extract_data {
  my ( $d, $i ) = @_;
  my $type = undef;

  # get the instance type string
  my @a = split( /","/, $d );

  if ( $type = $a[$i] ) {
    $type =~ s/(^"|"$)//;
  }

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

# calculate cost distribution
sub _calculateRICostSummary {
  my ($href_main) = @_;

  my $ref_value   = {};
  my $ProductCode = 'AmazonEC2';

  if ( exists( $href_main->{'BoxUsage'}->{'AmazonEC2'} ) ) {
    for my $k_RegionUsageType (
      keys %{ $href_main->{'BoxUsage'}->{'AmazonEC2'} } )
    {
      my $href_p =
        $href_main->{'BoxUsage'}->{'AmazonEC2'}->{$k_RegionUsageType};
      for my $k0 ( keys %{$href_p} )    # InstanceType
      {
        my $RegionCode        = undef;
        my $HURegionUsageType = 'HeavyUsage';

        # handle US-East RegionUsageType idiosyncracy
        if ( $k_RegionUsageType =~ /^(.+)-.+/ ) {
          $RegionCode = $1;
          $HURegionUsageType = join( '-', $RegionCode, $HURegionUsageType );
        }

        for my $k1 ( keys %{ $href_p->{$k0} } ) {
          my $refX = $href_p->{$k0}->{$k1};
          my $refY =
            $href_main->{'RawUsage'}->{$ProductCode}->{$k_RegionUsageType}
            ->{$k0};
          my $UsedPercentage =
            $refX->{'UsageQuantity'} / $refY->{'SumUsageQuantity'};

          my $ActualCost =
            $href_main->{'HeavyUsage'}->{$ProductCode}->{$HURegionUsageType}
            ->{$k0}->{'SumTotalCost'} * $UsedPercentage;

          my $key = $k1;
          $refY->{'Breakdown'}->{$key}->{'UsedPercentage'} = $UsedPercentage;
          $refY->{'Breakdown'}->{$key}->{'ActualCost'}     = $ActualCost;

          # put in summary
          if ( exists( $ref_value->{$key} ) ) {
            $ref_value->{$key} = $ref_value->{$key} + $ActualCost;
          }
          else {
            $ref_value->{$key} = $ActualCost;
          }
        }
      }
    }
  }

  return $ref_value;
}
