package Printer;

#############################################################################################################
#
#
#Finalidade: Este pacote cria uma abstracao entre o protocolo SNMP e elementos de rede do tipo
#impressora, obtendo informacoes como:
#	Nome, Fabricante, SystemContact, SystemLocation,
#	Alarmes e estado do elemento
#utilizando para isto as MIBs :
#		iso.org.dod.internet.mgmt.mib-2.system - 1.3.6.1.2.1.1
#		iso.org.dod.internet.mgmt.mib-2.host - 1.3.6.1.2.1.25
#		iso.org.dod.internet.mgmt.mib-2.printmib - 1.3.6.1.2.1.43
#autor: THIAGO GLAUCO SANCHEZ  -- Rocking --
#Linguagem: Perl
#arquivo: Printer.pm
#
#
#Multiplataforma: testado com Perl 5.8 ao 5.10 no Red-Hat, Solaris 10 e Windows 2003 sem alteracoes;
#
#
#
#############################################################################################################

use strict;
use warnings;
use Net::SNMP qw/:ALL/;
use Net::Ping;

our %alarmCode = (
	1	=>	'other',
	2	=>	'unknown',
	3	=>	'coverOpen',
	4	=>	'coverClosed',
	5	=>	'interlockOpen',
	6	=>	'interlockClosed',
	7	=>	'configurationChange',
	8	=>	'jam',
	501	=>	'doorOpen',
	502	=>	'doorClosed',
	503	=>	'powerUp',
	504	=>	'powerDown',
	801	=>	'inputMediaTrayMissing(801)',
	802	=>	'inputMediaSizeChange(802)',
	803	=>	'inputMediaWeightChange(803)',
	804	=>	'inputMediaTypeChange(804)',
	805	=>	'inputMediaColorChange(805)',
	806	=>	'inputMediaFormPartsChange(806)',
	807	=>	'inputMediaSupplyLow(807)',
	808	=>	'inputMediaSupplyEmpty(808)',
	901	=>	'outputMediaTrayMissing(901)',
	902	=>	'outputMediaTrayAlmostFull(902)',
	903	=>	'outputMediaTrayFull(903)',
	1001	=>	'markerFuserUnderTemperature(1001)',
	1002	=>	'markerFuserOverTemperature(1002)',
	1101	=>	'markerTonerEmpty(1101)',
	1102	=>	'markerInkEmpty(1102)',
	1103	=>	'markerPrintRibbonEmpty(1103)',
	1104	=>	'markerTonerAlmostEmpty(1104)',
	1105	=>	'markerInkAlmostEmpty(1105)',
	1106	=>	'markerPrintRibbonAlmostEmpty(1106)',
	1107	=>	'markerWasteTonerReceptacleAlmostFull(1107)',
	1108	=>	'markerWasteInkReceptacleAlmostFull(1108)',
	1109	=>	'markerWasteTonerReceptacleFull(1109)',
	1110	=>	'markerWasteInkReceptacleFull(1110)',
	1111	=>	'markerOpcLifeAlmostOver(1111)',
	1112	=>	'markerOpcLifeOver(1112)',
	1113	=>	'markerDeveloperAlmostEmpty(1113)',
	1114	=>	'markerDeveloperEmpty(1114)',
	1301	=>	'mediaPathMediaTrayMissing(1301)',
	1302	=>	'mediaPathMediaTrayAlmostFull(1302)',
	1303	=>	'mediaPathMediaTrayFull(1303)',
	1501	=>	'interpreterMemoryIncrease(1501)',
	1502	=>	'interpreterMemoryDecrease(1502)',
	1503	=>	'interpreterCartridgeAdded(1503)',
	1504	=>	'interpreterCartridgeDeleted(1504)',
	1505	=>	'interpreterResourceAdded(1505)',
	1506	=>	'interpreterResourceDeleted(1506)',
	1507	=>	'interpreterResourceUnavailable(1507)',
	);

sub new {

my ($class, $ip, $community) = @_;


	my $self = {
		IP=>$ip,
		Community=>$community,
		IsLive=> &checkIsLive($ip),
		Mibs => {mib_SysName => '1.3.6.1.2.1.1.5',
			 mib_SysObjID => '1.3.6.1.2.1.1.2',
			 mib_SysUpTime => '1.3.6.1.2.1.1.3',
			 mib_HrPrinterStatus => '1.3.6.1.2.1.25.3.5.1.1',
			 mib_HrDeviceStatus => '1.3.6.1.2.1.25.3.2.1.5',
			 mib_PrinterAlertCode => '1.3.6.1.2.1.43.18.1.1.7',
			 mib_PrintAlertsTable => '1.3.6.1.2.1.43.18.1',
			},
			 

		Session=>undef,
		Error=>undef,
		
		SysName=>undef,
		SysLocation=>undef,
		SysContact=>undef,
		SysObjID=>undef,
		SystemUpTime=>undef,
		
		ManufacturerCode=>undef,
		ManufacturerName=> undef,
		
		HrDeviceStatus=>undef,
		HrPrinterStatus=>undef,
		Status=>undef,

		PrinterAlertCode=>{Critical => 0,
				   Warning => 0,
				   Normal => 0,
				   NotEspecified => 0
				  },

		PrinterAlertMessages=>[]

	   };

	bless $self, $class;

	if ($self->{IsLive}){
		($self->{Session}, $self->{Error}) = 
			&snmpSession($self->{IP}, $self->{Community});
		if ($self->{Session}){
			$self->loadAllSNMP();
			($self->{ManufacturerName},$self->{ManufacturerCode}) = 
														$self->manufacturer;
		}
	}


	return $self;
}



sub snmpSession{
	my ($ip, $community) = @_;
	my ($connection,$err) = Net::SNMP->session(Hostname => $ip,
				Community => $community,
				Translate=>TRANSLATE_OCTET_STRING,
				);
	if (wantarray){
		return ($connection,$err);
	}
	return $connection;
}


sub checkIsLive{
	my $elemento = $_[0];

	my $ping = new Net::Ping;
	if (ref $elemento) {
		if ("Printer" eq (ref $elemento)){
			return 1 if $ping->ping($elemento->{IP}, 2);
		}
	}else{
		return 1 if $ping->ping($elemento, 2);
	}
	return 0;
}


sub snmpGetNext{
	my ($self,$arrVarbindlist) = @_;
	my $returnHash = $self->{Session}->get_next_request(Varbindlist=> $arrVarbindlist);
	return $returnHash;
}


sub snmpGetTable{
	my ($self,$scalarBaseOID) = @_;
	my $returnHash = $self->{Session}->get_table(-baseoid => $scalarBaseOID);
	return $returnHash;
}


sub loadAllSNMP{
	my $self=$_[0];
	my @direct = values %{$self->{Mibs}};
	my $snmpRequest = $self->snmpGetNext(\@direct);

	foreach (keys %$snmpRequest){
		$self->{SysName} = $snmpRequest->{$_} 
			if $_ =~ /^$self->{Mibs}->{mib_SysName}/;
		$self->{SysObjID} = $snmpRequest->{$_} 
			if $_ =~ /^$self->{Mibs}->{mib_SysObjID}/;
		$self->{SysUpTime} = $snmpRequest->{$_} 
			if $_ =~ /^$self->{Mibs}->{mib_SysUpTime}/;
		$self->{HrPrinterStatus} = $snmpRequest->{$_} 
			if $_ =~ /^$self->{Mibs}->{mib_HrPrinterStatus}/;
		$self->{HrDeviceStatus} = $snmpRequest->{$_} 
			if $_ =~ /^$self->{Mibs}->{mib_HrDeviceStatus}/;
	}

	my $alarmTable = $self->{Session}->get_table(
							-baseoid =>$self->{Mibs}->{mib_PrintAlertsTable});
							
	foreach(keys %{$alarmTable}){
		if ($_ =~ /^1\.3\.6\.1\.2\.1\.43\.18\.1\.1\.2/){
			++$self->{PrinterAlertCode}->{Critical} if $alarmTable->{$_} == 3;
			++$self->{PrinterAlertCode}->{Warning}  if $alarmTable->{$_} == 4;
			++$self->{PrinterAlertCode}->{Normal} if $alarmTable->{$_} == 1;
			++$self->{PrinterAlertCode}->{NotEspecified} 
									if (!($alarmTable->{$_} == 1 ||
									$alarmTable->{$_} == 4 ||
									$alarmTable->{$_} == 3));
		}elsif ($_ =~ /^1\.3\.6\.1\.2\.1\.43\.18\.1\.1\.7/){

			if (exists $alarmCode{$alarmTable->{$_}}){
				push @{$self->{PrinterAlertMessages}},$alarmCode{$alarmTable->{$_}};
			}else{
				push @{$self->{PrinterAlertMessages}}, $alarmTable->{$_} ;
			}
		}else{ 

			push @{$self->{PrinterAlertMessages}}, $alarmTable->{$_}
					if ($_ =~ /^1\.3\.6\.1\.2\.1\.43\.18\.1\.1\.8/);

		}#else{}
	
		
	}
}

sub manufacturer{
	my $self = $_[0];
	open FABRICANTES,"<enterprise.txt";
	my @objIDSplited = split /\./,$self->{SysObjID};
	while(<FABRICANTES>){
		if ($_ =~ /^$objIDSplited[6]\s/){
			chomp(my @str = split /\t/, $_);
			return ($str[1],$objIDSplited[6]) if wantarray;
			return $str[1];
			last;
		}
	}
}

sub DESTROY{
	my $self = $_[0];
	$self->{Session}->close if $self->{Session};
}




1
