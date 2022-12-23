#!/usr/bin/perl
##################################################################################
# Author        : ylu
# Data          : 2022.12.21
# Revision      : 0.2
# Purpose       : inject register fault and count error rate.
##################################################################################
#
###### updata log ######
# 22.12.19      first version.
# 22.12.21      complete random injection and result statistics output


########################## read tb and other information #########################
print "Please input testbench demo file:\n";
$tb_demo_file = "tb.demo";#<STDIN>;
chomp($tb_demo_file);
open (TB_DEMO, "<$tb_demo_file") or die "Can't open $tb_demo_file: $!";
@tb_demo = <TB_DEMO>;
close TB_DEMO;

print "Please input number of program runs:\n";
$program_num = "2";#<STDIN>;
chomp($program_num);

print "Please input start time of fault injection(unit:ns):\n";
$inject_start_time = "30";#<STDIN>;
chomp($inject_start_time);

print "Please input end time of fault injection(unit:ns):\n";
$inject_end_time = "150";#<STDIN>;
chomp($inject_end_time);

print "Please input number of injections per register:\n";
$inject_num_per_reg = "2";#<STDIN>;
chomp($inject_num_per_reg);


############################### read regs and inst ###############################
open (INST_DATA, "<inst.data") or die "Can't open inst.data: $!";
@inst_data = <INST_DATA>;
close INST_DATA;

open (REGS_DATA, "<regs.data") or die "Can't open regs.data: $!";
@regs_data = <REGS_DATA>;
close REGS_DATA;


############################# random fault injection #############################
@error_rate_data;
@fail_num_data;
foreach $a (@inst_data) {
    print "Start fault injection for module $a\n";
    my @regs;
    foreach $b (@regs_data) {
        if ($b =~ /$a/) {
            push (@regs, $b);
        }
    }
    my $fail_num = 0;
    for (my $i = 1 ; $i <= $program_num ; $i ++) {
        generate_tb(@regs);
        print "running times: $i\n";
        my $vcs_log = `make`;                             # don't use system() because system() will print the command 'make' results.
        if ($vcs_log !~ /V C S   S i m u l a t i o n   R e p o r t/) {
            die "vcs sim error.";
        }
        open (V_RESULT, "<vcs_result.data");
        my $v_result = <V_RESULT>;
        close V_RESULT;
        print "result: $v_result\n";
        if ($v_result =~ /FAIL/) {
            $fail_num ++;
        }
        printf "progress: %.2f\%\n",$i/$program_num*100;
    }

    my $error_rate = $fail_num/$program_num;
    print "module $a error number: $fail_num\n";
    push(@fail_num_data, $fail_num);
    printf "module $a Error Rate : %.2f\%\n\n",$error_rate*100;
    push(@error_rate_data, $error_rate*100);
}


############################## format output results #############################
$length_inst = 0;
$length_fail_num = 0;
$length_program_num = length($program_num);
foreach $a (@inst_data) {
    $a =~ s/^\s+//;
    $a =~ s/\s+$//;
    if (length($a) > $length_inst) {
        $length_inst = length($a);
    }
}
foreach $a (@fail_num_data) {
    $a =~ s/^\s+//;
    $a =~ s/\s+$//;
    if (length($a) > $length_fail_num) {
        $length_fail_num = length($a);
    }
}
$space=' ';
open (OUTPUT, ">error_rate.data") or die "Can't write error_rate.data: $!";
print OUTPUT "name".$space x ($length_inst-4+5).
"fail number".$space x (11+5).
"program number".$space x (14+5).
"error rate".$space x (10+5)."\n";
print OUTPUT '=' x (4+$length_inst-4+5+11+11+5+14+14+5+10)."\n";
for (my $n ; $n < @inst_data ; $n ++) {
    printf OUTPUT "$inst_data[$n]".$space x ($length_inst-length($inst_data[$n])+5).
    "$fail_num_data[$n]".$space x (11+5-length($fail_num_data[$n])+11).
    "$program_num".$space x (14+5-$length_program_num+14).
    "%.2f\%\n",$error_rate_data[$n];
}
close OUTPUT;


##################################################################################
#
#   sub functions
#
##################################################################################
=head1           generate testbench
    @INPUT  NONE
    @return NONE
        Testbench generating random excitation every time.
=cut
sub generate_tb {
    my (@regs) = @_;
    my @tb = @tb_demo;

    my $regs_size = scalar @regs;
    for (my $i = 1; $i <= $regs_size ; $i ++) {
        my $reg_num = int ( rand($regs_size) );

        if ($regs[$reg_num] =~ /(.*)\[(\d+):(\d+)\]/) {                 # multibit regs
            my $reg_bits = $1;
            my $high_bit = $2;
            my $low_bit  = $3;
            for (my $j = 0 ; $j < $inject_num_per_reg ; $j ++) {
                my $one_rand = int ( rand($high_bit-$low_bit+1) );
                my $two_rand = int ( rand($high_bit-$low_bit+1) );
                my $time = int ( rand($inject_end_time-$inject_start_time+1) ) + $inject_start_time;

                if ($one_rand > $two_rand) {
                    push(@tb, "initial begin\n");
                    push(@tb, "  #$time"."ns $reg_bits\[$one_rand\:$two_rand\] = ~$reg_bits\[$one_rand\:$two_rand\];\n");
                    push(@tb, "end\n");
                    push(@tb, "\n");
                }
                elsif ($two_rand > $one_rand) {
                    push(@tb, "initial begin\n");
                    push(@tb, "  #$time"."ns $reg_bits\[$two_rand\:$one_rand\] = ~$reg_bits\[$two_rand\:$one_rand\];\n");
                    push(@tb, "end\n");
                    push(@tb, "\n");
                }
                elsif ($two_rand == $one_rand) {
                    push(@tb, "initial begin\n");
                    push(@tb, "  #$time"."ns $reg_bits\[$one_rand\] = ~$reg_bits\[$one_rand\];\n");
                    push(@tb, "end\n");
                    push(@tb, "\n");
                }
            }
            
        }
        else {                                                      # single bit reg
            for (my $j = 0 ; $j < $inject_num_per_reg ; $j ++) {
                my $time = int ( rand($inject_end_time-$inject_start_time+1) ) + $inject_start_time;

                push(@tb, "initial begin\n");
                push(@tb, "  #$time"."ns $regs[$reg_num] = ~$regs[$reg_num];\n");
                push(@tb, "end\n");
                push(@tb, "\n");
            }
        }

    }
    foreach $a (@tb) {
        $a =~ s/endmodule//;
    }
    push(@tb, "endmodule\n");

    open (TB_RESULT, ">tb.v") or die "Can't write tb.v: $!";
    print TB_RESULT @tb;
    close TB_RESULT;
}