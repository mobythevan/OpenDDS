eval '(exit $?0)' && eval 'exec perl -S $0 ${1+"$@"}'
    & eval 'exec perl -S $0 $argv:q'
    if 0;

# $Id$
# -*- perl -*-

use Env (DDS_ROOT);
use lib "$DDS_ROOT/bin";
use Env (ACE_ROOT);
use lib "$ACE_ROOT/bin";
use DDS_Run_Test;

$status = 0;

PerlDDS::add_lib_path('../FooType4');

# single reader with single instances test
$multiple_instance=0;
$num_samples_per_reader=3;
$num_readers=1;
$use_take=0;

$domains_file = "domain_ids";
$dcpsrepo_ior = "repo.ior";
$repo_bit_conf = "-ORBSvcConf ../../tcp.conf";

unlink $dcpsrepo_ior;
unlink $pub_id_file;

# -ORBDebugLevel 1 -ORBSvcConf ../../tcp.conf

$DCPSREPO = PerlDDS::create_process ("$ENV{DDS_ROOT}/bin/DCPSInfoRepo",
                                    "$repo_bit_conf -o $dcpsrepo_ior"
                                    . " -d $domains_file");

$svc_config=" -ORBSvcConf ../../tcp.conf ";
$parameters = "$svc_config -r $num_readers -t $use_take"
              . " -m $multiple_instance -i $num_samples_per_reader " ;

if ($ARGV[0] eq 'udp') {
  $parameters .= " -ORBSvcConf udp.conf -us -s localhost:16701 -up -p localhost:29803";
}
if ($ARGV[0] eq 'give_addrs') {
  $parameters .= " -s localhost:16701 -p localhost:29803";
}
elsif ($ARGV[0] eq 'diff_trans') {
  $parameters .= " -ORBSvcConf udp.conf -up -p localhost:29803";
}

$FooTest5 = PerlDDS::create_process ("main", $parameters);

print $DCPSREPO->CommandLine(), "\n";
$DCPSREPO->Spawn ();

if (PerlACE::waitforfile_timed ($dcpsrepo_ior, 30) == -1) {
    print STDERR "ERROR: waiting for DCPSInfo IOR file\n";
    $DCPSREPO->Kill ();
    exit 1;
}

print $FooTest5->CommandLine(), "\n";
$FooTest5->Spawn ();

$result = $FooTest5->WaitKill (60);

if ($result != 0) {
    print STDERR "ERROR: main returned $result \n";
    $status = 1;
}


$ir = $DCPSREPO->TerminateWaitKill(5);

if ($ir != 0) {
    print STDERR "ERROR: DCPSInfoRepo returned $ir\n";
    $status = 1;
}

if ($status == 0) {
  print "test PASSED.\n";
}
else {
  print STDERR "test FAILED.\n";
}
exit $status;
