#!/usr/bin/perl

use strict;
use warnings;

my $href_Data = {};

# TODO:
# - find the discrepancy on RDS, sum of distribution < actual cost

# NOTE: 
# - on UsageType: for US-East, region information is not included 
#   (e.g. HeavyUsage only instead of SG's APS1-HeavyUsage)

while (<>) {
  chomp;

  my $LinkedAccountId   = _extract_data( $_, 2 );     # LinkedAccountId
  my $LinkedAccountName = _extract_data( $_, 9 );     # LinkedAccountName
  my $ProductCode       = _extract_data( $_, 12 );    # ProductCode
  my $UsageType         = _extract_data( $_, 15 );    # UsageType
  my $UsageQuantity     = _extract_data( $_, 22 );    # UsageQuantity
  my $TotalCost         = _extract_data( $_, 29 );    # TotalCost
  # NOTE: for custom tags, the column location can change
  my $CostCodeCategory  = _extract_data( $_, 32 );    # CostCodeCategory

  if ( not $UsageType ) { next; }

  # drop the instance type data, not relevant since RI applies to all
  # type of instances under the same family (e.g. t2, m3, c4, etc.)
  my ( $RegionUsageType, undef ) = split( /:/, $UsageType );

  # Get all RIs
  if ( $_ =~ /Amazon(EC2|RDS).+HeavyUsage.+hourly fee/ ) {

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
  elsif ( $_ =~ /Amazon(EC2|RDS).+Usage.+reserved instance applied/ ) {

    # get from the description
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

my $href_EC2RICostSummary = _calculateRICostSummary( $href_Data, 'AmazonEC2' );
my $href_RDSRICostSummary = _calculateRICostSummary( $href_Data, 'AmazonRDS' );

_print_href( 'AmazonEC2', $href_EC2RICostSummary );
_print_href( 'AmazonRDS', $href_RDSRICostSummary );

# sub functions
sub _extract_data {
  my ( $d, $i ) = @_;
  my $type = undef;

  # get the instance type string
  my @a = split( /","/, $d );

  if ( $type = $a[$i] ) {
    $type =~ s/(^"|"$)//;
  }
  else {
    $type = '';
  }

  return $type;
}

sub _get_RI_applied_type {
  my $d     = shift @_;
  my $value = undef;

  my $ItemDescription = _extract_data( $d, 19 );
  my $UsageType       = _extract_data( $d, 15 );    # UsageType
  if ( $ItemDescription =~ /^(.+), (.+) reserved instance applied/ ) {
    $value = "$2|$1";

    if ( $UsageType =~ /Multi-AZ/ ) {
      $value = "$value|MultiAZ";
    }
  }

  return $value;
}

sub _get_RI_purchased_type {
  my $d     = shift @_;
  my $value = undef;

  my $ItemDescription = _extract_data( $d, 19 );
  if ( $ItemDescription =~ /per (.+), (.+) instance/ ) {
    $value = "$2|$1";

    # mark if it's a RDS Multi-AZ RI
    # TODO: FIX HARD CODED STUFF!
    if (
      $ItemDescription =~
      /^USD 0.0416 hourly fee per MySQL, db.t2.micro instance/        # verified
      or $ItemDescription =~
      /^USD 0.0272 hourly fee per MySQL, db.t2.micro instance/        # verified
      or $ItemDescription =~
      /^USD 0.169 hourly fee per MySQL, db.m3.medium instance/        # verified
      or $ItemDescription =~
      /^USD 0.364 hourly fee per MySQL, db.m4.large instance/         # verified
      or $ItemDescription =~
      /^USD 0.178 hourly fee per PostgreSQL, db.m3.medium instance/   # verified
      or $ItemDescription =~
      /^USD 0.38 hourly fee per PostgreSQL, db.m4.large instance/     # verified
      or $ItemDescription =~
      /^USD 0.169 hourly fee per Oracle EE \(BYOL\), db.m3.medium instance/ # verified
      or $ItemDescription =~
      /^USD 0.364 hourly fee per Oracle EE \(BYOL\), db.m4.large instance/ # verified
      )
    {
      $value = "$value|MultiAZ";
    }
  }

  return $value;
}

# calculate cost distribution
sub _calculateRICostSummary {
  my ( $href_main, $ProductCode ) = @_;

  my $ref_value = {};

  # my $ProductCode = 'AmazonEC2';

  if ( exists( $href_main->{'BoxUsage'}->{$ProductCode} ) ) {
    for my $k_RegionUsageType (
      keys %{ $href_main->{'BoxUsage'}->{$ProductCode} } )
    {
      my $href_p =
        $href_main->{'BoxUsage'}->{$ProductCode}->{$k_RegionUsageType};
      for my $k0 ( keys %{$href_p} )    # InstanceType
      {
        my $RegionCode        = undef;
        my $HURegionUsageType = 'HeavyUsage';

        # handle US-East RegionUsageType idiosyncracy
        if ( $k_RegionUsageType =~ /^(.{4})-.+/ ) {
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

          if (
            not exists(
              $href_main->{'HeavyUsage'}->{$ProductCode}->{$HURegionUsageType}
                ->{$k0}->{'SumTotalCost'}
            )
            )
          {
            warn "Error: RI not found $ProductCode, "
              . "UsageType: $HURegionUsageType, "
              . "InstanceType: $k0\n";
            next;
          }

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

sub _print_href {
  my ($prefix, $href) = @_;

  for my $key (keys %$href) {
    print join(',', $prefix, $key, $href->{$key}) . "\n";
  }
}
