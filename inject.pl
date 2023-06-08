#!/usr/bin/perl
##################################################################################
# Author        : ylu
# Data          : 2023.02.21
# Revision      : 0.6
# Purpose       : inject register fault and count error rate.
##################################################################################
#
###### updata log ######
# 22.12.19      first version.
# 22.12.21      complete random injection and result statistics output
# 22.12.23      add support for removing modules without regs.
# 22.12.30      fix bug of identification regs.
#               optimize formatted output results.
# 23.02.20      modify fault injection mode.
# 23.02.21      add reporting timeout numbers.
# 23.04.13      add single register fault injection.



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

print "Please input single(1) or all(0) regs injection:\n";
$single_inject_flag = "1";
chomp($single_inject_flag);

############################### read regs and inst ###############################
open (INST_DATA, "<inst.data") or die "Can't open inst.data: $!";
@inst_data = <INST_DATA>;
close INST_DATA;

open (REGS_DATA, "<regs.data") or die "Can't open regs.data: $!";
@regs_data = <REGS_DATA>;
close REGS_DATA;


############################# random fault injection #############################
$regs_lines = join ('===', @regs_data);

# format output results
$length_inst = 0;
$length_program_num = length($program_num);
foreach $a (@inst_data) {
    $a =~ s/^\s+//;
    $a =~ s/\s+$//;
    if (length($a) > $length_inst) {
        $length_inst = length($a);
    }
}
$space=' ';
open (OUTPUT, ">error_rate.data") or die "Can't write error_rate.data: $!";
if ($single_inject_flag == 1) {
    print OUTPUT "name".$space x ($length_inst-4+5).
    "rec success num".$space x (5).
    "rec fail num".$space x (5).
    "inject success num".$space x (5).
    "total inject num".$space x (5).
    "error rate\n";
    print OUTPUT '=' x (4+$length_inst-4+5 +15+5 +12+5 +18+5 +16+5 +10)."\n";
}
else {
    print OUTPUT "name".$space x ($length_inst-4+5).
    "sim fail num".$space x (5).
    "timeout num".$space x (5).
    "fail num".$space x (5).
    "run num".$space x (5).
    "error rate\n";
    print OUTPUT '=' x (4+$length_inst-4+5 +12+5 +11+5 +8+5 +7+5 +10)."\n";
}

foreach $a (@inst_data) {
    $a =~ s/^\s+//;
    $a =~ s/\s+$//;
    
    if ($regs_lines =~ /$a\.[^\.]*===/) {      # module with regs
        print "Start fault injection for module $a\n";
        my @regs;
        foreach $b (@regs_data) {
            if ($b =~ /$a\.[^\.]*$/) {
                push (@regs, $b);
            }
        }
        if ($single_inject_flag == 1) {         # single reg injection
            foreach $c (@regs) {                # inject faults into each register
                fault_injection($a, $c);
            }
        }
        else {
            fault_injection($a, @regs);
        }
    }
    else {      # module without regs
        print "module $a don't have regs.\n";
        if ($single_inject_flag == 1){
            printf OUTPUT "$a".$space x ($length_inst-length($a)+5).
            "-".$space x (15+5-1).
            "-".$space x (12+5-1).
            "-".$space x (18+5-1).
            "-".$space x (16+5-1).
            "No Regs\n";
        }
        else {
            printf OUTPUT "$a".$space x ($length_inst-length($a)+5).
            "-".$space x (12+5-1).
            "-".$space x (11+5-1).
            "-".$space x (8+5-1).
            "-".$space x (7+5-1).
            "No Regs\n";
        }
    }
}
close OUTPUT;



##################################################################################
#
#   sub functions
#
##################################################################################
=head1           fault injection
    @INPUT  NONE
    @return NONE
        Fault injection process.
=cut
sub fault_injection {
    my ($a, @regs) = @_;
    my $fail_num = 0;
    my $timeout_num = 0;
    my $inject_success_num_total = 0;
    for (my $i = 1 ; $i <= $program_num ; $i ++) {
        generate_tb(@regs);
        print "running times: $i\n";
        my $v_result;
        my $vcs_error = 0;
        my $vcs_log = `make`;                             # don't use system() because system() will print the command 'make' results.
        if ($vcs_log !~ /V C S   S i m u l a t i o n   R e p o r t/) {
            print "vcs sim error.\n";
            $v_result = "FAIL";
            $vcs_error = 1;
        }
        else {
            open (V_RESULT, "<vcs_result.data");
            $v_result = <V_RESULT>;
            close V_RESULT;
        }
        print "result: $v_result\n";
        if ($v_result =~ /FAIL/) {
            $fail_num ++;
        }
        elsif ($v_result =~ /TIMEOUT/) {
            $fail_num ++;
            $timeout_num ++;
        }

        my $inject_success_num;
        if ($single_inject_flag == 1) {
            open (FAULT_RESULT, "<inject_success.data");
            $inject_success_num = <FAULT_RESULT>;
            close FAULT_RESULT;
            $inject_success_num =~ /(\d+)/;
            $inject_success_num = $1;
            $inject_success_num_total = $inject_success_num_total + $inject_success_num;
        }

        printf "progress: %.2f\%\n",$i/$program_num*100;
    }

    my $sim_fail_num;
    my $error_rate;
    if ($single_inject_flag == 1) {
        if ($inject_success_num_total != 0) {
            $error_rate = $fail_num/$inject_success_num_total;
        }
        else {
            $error_rate = 0;
        }
    }
    else {
        $error_rate = $fail_num/$program_num;
    }

    $sim_fail_num = $fail_num - $timeout_num;
    
    if ($single_inject_flag == 1){
        printf "$regs[0] Error Rate : %.2f\%\n\n",$error_rate*100;

        my $rec_success_num = $inject_success_num_total - $fail_num;
        my $rec_fail_num = $fail_num;
        my $total_inject_num = $program_num*$inject_num_per_reg;

        if ($vcs_error == 1) {
            printf OUTPUT "$a".$space x ($length_inst-length($a)+5).
            "-".$space x (15+5-1).
            "-".$space x (12+5-1).
            "-".$space x (18+5-1).
            "-".$space x (16+5-1).
            "VCS SIM ERROR\n";
        }
        else {
            printf OUTPUT "$regs[0]".$space x ($length_inst-length($regs[0])+5).
            "$rec_success_num".$space x (15+5-length($rec_success_num)).
            "$rec_fail_num".$space x (12+5-length($rec_fail_num)).
            "$inject_success_num_total".$space x (18+5-length($inject_success_num_total)).
            "$total_inject_num".$space x (16+5-length($total_inject_num)).
            "%.2f\%\n",$error_rate*100;
        }
    }
    else {
        print "module $a error number: $fail_num\n";
        printf "module $a Error Rate : %.2f\%\n\n",$error_rate*100;
        if ($vcs_error == 1) {
            printf OUTPUT "$a".$space x ($length_inst-length($a)+5).
            "-".$space x (12+5-1).
            "-".$space x (11+5-1).
            "-".$space x (8+5-1).
            "-".$space x (7+5-1).
            "VCS SIM ERROR\n";
        }
        else {
            printf OUTPUT "$a".$space x ($length_inst-length($a)+5).
            "$sim_fail_num".$space x (12+5-length($sim_fail_num)).
            "$timeout_num".$space x (11+5-length($timeout_num)).
            "$fail_num".$space x (8+5-length($fail_num)).
            "$program_num".$space x (7+5-$length_program_num).
            "%.2f\%\n",$error_rate*100;
        }
    }
}

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
                    push(@tb, "reg \[$one_rand\:$two_rand\] tmp\_$i\_$j;\n");
                    push(@tb, "initial begin\n");
                    push(@tb, "  tmp\_$i\_$j = 'b0;\n");
                    push(@tb, "  #$time"."ns tmp\_$i\_$j = ~$reg_bits\[$one_rand\:$two_rand\];\n");
                    push(@tb, "    force $reg_bits\[$one_rand\:$two_rand\] = tmp\_$i\_$j;\n");
                    push(@tb, "  #10ns release $reg_bits\[$one_rand\:$two_rand\];\n");
                    push(@tb, "end\n");
                    push(@tb, "\n");
                }
                elsif ($two_rand > $one_rand) {
                    push(@tb, "reg \[$two_rand\:$one_rand\] tmp\_$i\_$j;\n");
                    push(@tb, "initial begin\n");
                    push(@tb, "  tmp\_$i\_$j = 'b0;\n");
                    push(@tb, "  #$time"."ns tmp\_$i\_$j = ~$reg_bits\[$two_rand\:$one_rand\];\n");
                    push(@tb, "    force $reg_bits\[$two_rand\:$one_rand\] = tmp\_$i\_$j;\n");
                    push(@tb, "  #10ns release $reg_bits\[$two_rand\:$one_rand\];\n");
                    push(@tb, "end\n");
                    push(@tb, "\n");
                }
                elsif ($two_rand == $one_rand) {
                    push(@tb, "reg tmp\_$i\_$j;\n");
                    push(@tb, "initial begin\n");
                    push(@tb, "  tmp\_$i\_$j = 'b0;\n");
                    push(@tb, "  #$time"."ns tmp\_$i\_$j = ~$reg_bits\[$one_rand\];\n");
                    push(@tb, "    force $reg_bits\[$one_rand\] = tmp\_$i\_$j;\n");
                    push(@tb, "  #10ns release $reg_bits\[$one_rand\];\n");
                    push(@tb, "end\n");
                    push(@tb, "\n");
                }
            }
            
        }
        else {                                                      # single bit reg
            for (my $j = 0 ; $j < $inject_num_per_reg ; $j ++) {
                my $time = int ( rand($inject_end_time-$inject_start_time+1) ) + $inject_start_time;

                my $regs_bit = $regs[$reg_num];
                $regs_bit =~ s/^\s+//;
                $regs_bit =~ s/\s+$//;
                push(@tb, "reg tmp\_$i\_$j;\n");
                push(@tb, "initial begin\n");
                push(@tb, "  tmp\_$i\_$j = 'b0;\n");
                push(@tb, "  #$time"."ns tmp\_$i\_$j = ~$regs_bit;\n");
                push(@tb, "    force $regs_bit = tmp\_$i\_$j;\n");
                push(@tb, "  #10ns release $regs_bit;\n");
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