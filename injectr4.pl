#!/usr/bin/perl
#################################################################################
# Author        : ylu
# Data          : 2022.12.17
# Revision      : 1.4
# Purpose       : Find all regs.
#################################################################################
#
# !!!!!!!!!!!!!!!!!!!!! Warning !!!!!!!!!!!!!!!!!!!!!!
# !! *Please use standard verilog code.             !!
# !! *Not support SystemVerilog.                    !!
# !! *Not support macros with the same name.        !!
# !!     eg. `undef in Synopsys DW IP.              !!
# !! *Not support Very Complex situatiions.         !!
# !!!!!!!!!!!!!!!!!!!!! Warning !!!!!!!!!!!!!!!!!!!!!!
#
###### updata log ######
# 22.12.13      identify modules and files, find out basic regs.
# 22.12.14      fix bug that can't identify parameterized instance module.
# 22.12.15      add identification macro defination code blocks.
# 22.12.17      add support parameterized regs.


############################# read verilog filelist #############################
print "Please input verilog filelist name:\n";
$verilog_files = "filelist.f";#<STDIN>;
chomp($verilog_files);
open (V_FILELIST, "<$verilog_files") or die "Can't open $verilog_files: $!";
@file_list = <V_FILELIST>;
close V_FILELIST;

print "Please input top module name:\n";
$top_module = "test_top";#<STDIN>;
chomp($top_module);

print "Please input macrolist name:\n";
$macrolist_name = "macrolist.f";#<STDIN>;
chomp($macrolist_name);
open (MACRO_LIST, "<$macrolist_name") or die "Can't open $macrolist_name: $!";
@macro_list = <MACRO_LIST>;
close MACRO_LIST;


############################### clear verilog code ##############################
# First, filter out verilog code comments.
# And Pick the part that meets the macro definition.
mkdir "pure_files";
open (V_FILELIST_PURE, ">filelist_pure.f") or die "Can't write filelist_pure.f: $!";
foreach $a (@file_list) {
    clear_verilog($a, @macro_list);
}
close V_FILELIST_PURE;

open (V_FILELIST_PURE, "<filelist_pure.f");
@file_list_pure = <V_FILELIST_PURE>;
close V_FILELIST_PURE;


############################# find common parameters ############################
# find all common parameters for replacing parameters with numbers later.
@param_common_name;
@param_common_number;
foreach $a (@file_list_pure) {
    open (DEFINE_TMP, "<$a") or die "Can't open $a, $!";
    my @file = <DEFINE_TMP>;
    close DEFINE_TMP;
    foreach $b (@file) {
         # In Veriog, parameters defined by parameter can only be accessed directly, 
         # and parameters define by `define can only be accessed by `
        if($b =~ /\`define\s+(\w+)\s+(.*)$/){              
            push(@param_common_name, $1);
            push(@param_common_number, $2);
        }
    }
}


################################ find all modules ###############################
# Find all modules' name.
# This is used for finding the module instantiation relationship later.
@all_module_name;
@module_file_result;
foreach $filename (@file_list_pure) {
    open (FILE_FOR_MODULE, "<$filename") or die "Can't open $filename, $!";
    my @file = <FILE_FOR_MODULE>;
    foreach $a (@file) {
        if($a =~ /\s*module\s+(\w+)\s*?\(?/){
            push(@all_module_name, $1);
            push(@module_file_result, "$1$filename");
        }
    }
    close FILE_FOR_MODULE;
}
# save module and file correspondence to module_file.data
open (MODULE_FILE_RESULT, ">module_file.data") 
    or die "Can't write module_file.data: $!";
print MODULE_FILE_RESULT @module_file_result;
close MODULE_FILE_RESULT;
print "all module : @all_module_name\n";


###################### find reg/instantiation relationship ######################
open (REGS_RESULT, ">regs.data") or die "Can't write regs.data: $!";
open (INST_DATA, ">inst.data") or die "Can't write inst.data: $!";
$name_inst = $top_module;
@file = find_module($name_inst);
find_signals($name_inst, @file);
find_inst(@file);
close INST_DATA;
close REGS_RESULT;


#################################################################################
#
#   sub functions
#
#################################################################################
=head1       clear verilog code
    @INPUT  $file_name_original, @macro_list
    @return NONE
        delete the comment code, and find out the macro definition code.
=cut
sub clear_verilog {
    my ($file_name_original, @macro_list) = @_;

    open (FILE_TMP, "<$file_name_original") or die "Can't open $file_name_original, $!";
    my @vfile = <FILE_TMP>;
    close FILE_TMP;

    my @macro_start_num;
    my @macro_end_num;

    ###### clear comment code ######
    my $flag = 0;
    my $flag_macro = 0;                     # prevent macro code blocks including macro code blocks.
    for(my $i = 0; $i < @vfile ; $i++) {
        $vfile[$i] =~ s/\/\/.*//g;          # clear // commented code
        $vfile[$i] =~ s/\/\*.*?\*\///g;     # clear /**/ single line comment code
        
        if ($vfile[$i] =~ /\*\//) {         # clear /**/ multiline comment code
            $flag = 0;
            $vfile[$i] =~ s/.*\*\///g;
            if($vfile[$i] =~ /\/\*/) {      # prevent this situation: " */ code /* "
                $flag = 1;
                $vfile[$i] =~ s/\/\*.*//g;
            }
        }
        elsif ($vfile[$i] =~ /\/\*/){
            $flag = 1;
            $vfile[$i] =~ s/\/\*.*//g;
        }
        elsif ($flag == 1) {
            $vfile[$i] =~ s/.*//g;
        }

        if ($vfile[$i] =~ /\`ifn?def/){         # find out the macro code number
            if ($flag_macro == 0) {             # first meet
                push(@macro_start_num, $i);
            }
            $flag_macro ++;
        }
        if ($vfile[$i] =~ /\`endif/){
            if ($flag_macro == 1) {             # last end meet
                push(@macro_end_num, $i);
            }
            $flag_macro --;
        }
    }
    
    ###### find out the macro definition code ######
    # If there are multiple macro code blocks in verilog file, 
    # the array @macro_start_num and @macro_end_num records the number of start and end lines number
    # of each macro code block.

    # After that, use two "for" loops to traverse each macro code block,
    # and delete the part that does not belong to the macro(in macrolist).

    for (my $i = 0 ; $i < @macro_start_num ; $i ++) {
        my @macro_next;
        for (my $k = $macro_start_num[$i] ; $k <= $macro_end_num[$i] ; $k ++) {
            push(@macro_next, $vfile[$k]);
        }
        @vfile[$macro_start_num[$i]...$macro_end_num[$i]] = find_macro(@macro_next);
    }

    ###### delete blank lines ######
    my @vfile_real;
    foreach $a (@vfile) {
        if ($a =~ /\w|\(|\)/){
            push (@vfile_real, $a);
        }
    }

    $file_name_original =~ /(\w+)\.v/;
    my $file_name_pure = "pure_".$1.".v";
    print V_FILELIST_PURE "./pure_files/$file_name_pure\n";
    open (PURE_CODE, ">./pure_files/$file_name_pure") or die "Can't write $file_name_pure: $!";
    print PURE_CODE @vfile_real;
    close PURE_CODE;

}

=head1            find macro code block
    @INPUT  @macro_code block
    @return @macro_code block after clearing.
        Use the recursion idea to find the deepest macro code block.
        When the "for" loop recurses to the deepest layer, the obtained macro code block
            is simple and no longer contains the macro code block.
        After the "for" loop ends, clean up the macro code block, delete the unnecessary code,
            and then return to the recursive function of the upper layer.
=cut
sub find_macro {
    my (@macro_code) = @_;
    
    my $flag = 0;
    my $start_num;
    my $end_num;
    my @macro_next;

    # "for" loop for recursion.
    for (my $i = 0; $i < @macro_code ; $i ++) {
        if ($macro_code[$i] =~ /\`ifn?def/ && $i != 0) {
            if ($flag == 0) {
                $start_num = $i;
            }
            $flag ++;
            push(@macro_next, $macro_code[$i]);
        }
        elsif ($macro_code[$i] =~ /\`endif/ && $flag > 0) {
            $flag --;
            push(@macro_next, $macro_code[$i]);
            if ($flag == 0){                # finding finish
                $end_num = $i;
                @macro_code[$start_num...$end_num] = find_macro(@macro_next);
                
            }
        }
        elsif ($flag > 0) {
            push(@macro_next, $macro_code[$i]);
        }
    }

    # $any_macro_exist record whether there is a macro(in macrolist) in macro code block.
    # If it exists, the $any_macro record the macro name.

    my $flag_find_macro = 0;
    my $any_macro;
    my $any_macro_exist;
    for (my $i = 0 ; $i < @macro_code ; $i ++) {
        # All macro definitions are traversed for each line.
        # If any, the loop is exited, and the required macro definition name is selected.
        foreach $macro_name (@macro_list) {
            $macro_name =~ s/^\s+//;
            $macro_name =~ s/\s+$//;
            if ($macro_code[$i] =~ /\`ifn?def\s+$macro_name\b/ ||
                $macro_code[$i] =~ /\`elsif\s+$macro_name\b/) {
                $flag_find_macro = 1;
                $any_macro = $macro_name;
                last;
            }
        }
        if ($flag_find_macro == 1) {
            $flag_find_macro = 0;
            $any_macro_exist = 1;
            last;
        } else {
            $any_macro_exist = 0;
            next;
        }
    }

    $flag = 0;
    # `ifndef $macro, but we define the $macro, so code after `else/`elsif is left.
    if ($macro_code[0] =~ /\`ifndef\s+$any_macro\b/
       && $any_macro_exist == 1) {
        $any_macro_exist = 0;
        # "for" loop aviod this situation: there have `elsif $macro after `ifndef, and the $macro is defined.
        for (my $i = 0 ; $i < @macro_code ; $i ++) {
            foreach $macro_name (@macro_list) {
                $macro_name =~ s/^\s+//;
                $macro_name =~ s/\s+$//;
                if ($macro_code[$i] =~ /\`elsif\s+$macro_name\b/) {
                    $flag_find_macro = 1;
                    $any_macro = $macro_name;
                    last;
                }
            }
            if ($flag_find_macro == 1) {
                $flag_find_macro = 0;
                $any_macro_exist = 1;
                last;
            } else {
                $any_macro_exist = 0;
                next;
            }
        }
    } 
    # `ifndef $macro, and we don't define the $macro, so code before `else/`elsif is left.
    elsif ($macro_code[0] =~ /\`ifndef\s+(\w+)/) {
        $any_macro_exist = 1;
        $any_macro = $1;
        $macro_code[0] =~ s/\`ifndef/\`ifdef/;
    }

    # Traverse a macro code block
    foreach $a (@macro_code) {
        # When the macro is not found in macro code block, the code after `else is left.
        if ($any_macro_exist == 0) {
            if ($a =~ /\`else/) {
                $flag = 1;
                $a =~ s/\`else.*//;
            }
            elsif (($flag == 1) && ($a =~ /\`endif/)) {
                $flag = 0;
                $a =~ s/.*//;
            }
            elsif ($flag == 0) {
                $a =~ s/.*//;
            }
        }
        else {
            if ($a =~ /\`ifdef\s+$any_macro\b/ ||
                $a =~ /\`elsif\s+$any_macro\b/) {
                $flag = 1;
                $a =~ s/.*//;
            }
            elsif (($flag == 1) &&
                ($a =~ /\`else/ || $a =~ /\`elsif/ || $a =~ /\`endif/)) {
                $flag = 0;
                $a =~ s/.*//;
            }
            elsif ($flag == 0) {
                $a =~ s/.*//;
            }
        }
    }

    return @macro_code;
}

=head1       find module
    @INPUT  $module_name
    @return @file_real
        If there are multiple modules in a .v file, 
            this function is used for filter out the module used.
=cut
sub find_module {
    my ($module_name) = @_;

    my $file_name;
    foreach $a (@module_file_result) {
        if ($a =~ /$module_name(.*).v/) {
            $file_name = "$1.v";
            last;
        }
    }
    open (FILE_TMP, "<$file_name") or die "Can't open $file_name: $!";
    my @file = <FILE_TMP>;
    close FILE_TMP;

    my @file_real;
    my $flag=0;
    foreach $a (@file) {
        if($a =~ /\`include/) {
            push(@file_real, $a);
        }
        if($a =~ /module\s+$module_name/) {
            $flag = 1;
        }
        if($a =~ /endmodule/) {
            $flag = 0;
        }
        if($flag == 1) {
            push(@file_real, $a);
        }
    }

    return @file_real;
}

=head1      find instantiation relationship
    @INPUT  @file
    @return NONE
        Use the recursion idea to find the deepest instantiation module.
        when the "for" and "foreach" loop recurses to the deepest layer,
            the module is no longer contains instantiation module.
=cut
sub find_inst {
    my (@file) = @_;
    for(my $i = 0 ; $i < @file ; $i ++) {
        foreach $a (@all_module_name) {
            if( $file[$i] =~ /\b$a\b/) {
                # When instantiation occurs, select a certain amount of code from this line 
                # to determine the instance name.
                # So, the "18" is only a range selected by experience.
                # It is necessary to ensure that the instance name is included in $lines when it appears.
                my $lines = join ('', @file[$i..$i+18]);
                # match count, record how many $a in $lines.
                my $count = () = $lines =~ /\b$a\b/g;
                # If $lines contains multiple instantiations, select the most recent instantiation module.
                while($count > 1){
                    $lines =~ /(.*)\b$a\b(.*)/s;
                    $lines = $1;
                    $count--;
                }
                if(($lines !~ /module\s+$a\b/) &&                     # it avoids identifying "module $a"
                   (($lines =~ /$a\s+(\w+)\s*?\(/s) ||                # module_name u_mod();
                   ($lines =~ /$a\s*?\#\s*?\([\s|\S]*?\)\s*?(\w+).*?\(/s))  # module_name #() u_mod();
                   ){
                    my $name_inst_tmp = $name_inst;
                    $name_inst .= ".".$1;
                    print INST_DATA "$name_inst\n";
                    print "$name_inst\n";
                    my @file_real = find_module($a);
                    my $param_in;
                    if ($lines =~ /$a\s*?\#\s*?\(([\s|\S]*?)\)\s*?(\w+).*?\(/s) {
                        $param_in = $1;
                    }
                    my @file_real_noparam = replace_param($param_in, @file_real);
                    find_signals($name_inst, @file_real_noparam);
                    find_inst(@file_real);
                    $name_inst = $name_inst_tmp;
                }
            }
        }
    }
}

=head1     replace parameters with numbers.
    @INPUT  $param_in, @file
    @return @file after replacing
=cut
sub replace_param {
    my ($param_in, @file) = @_;

    my @param_self_name;
    my @param_self_number;

    # find self parameters.
    my $lines = join ('', @file);
    while ( $lines =~ /parameter\s+([\s|\S]*?);/g ) {
        my $tmp = $1;
        while ($tmp =~ /([\s|\S]*?),([\s|\S]*)/g) {                 # avoid "localparam AA = 2 , BB = 2'h1;"
            $tmp = $2;
            my $tmp_2 = $1;
            if ($tmp_2 =~ /(\w+)\s*?=\s*?(.*)/g) {
                push(@param_self_name, $1);
                my $tmp_number = $2;
                $tmp_number =~ s/^\s+//;
                $tmp_number =~ s/\s+$//;
                push(@param_self_number, $tmp_number);
            }
        }
        if ($tmp =~ /(\w+)\s*?=\s*?(.*)/g) {
            push(@param_self_name, $1);
            my $tmp_number = $2;
            $tmp_number =~ s/^\s+//;
            $tmp_number =~ s/\s+$//;
            push(@param_self_number, $tmp_number);
        }
    }

    my @param_transmit_name;
    my @param_transmit_number;
    my $num = 0;
    # get the parameters passed in.
    while ($param_in =~ /([\s|\S]*?),([\s|\S]*)/g) {
        my $tmp = $1;
        $param_in = $2;
        if ($tmp =~ /\.(\w+)\s*?\(([\s|\S]*)\)/g) {                 # "#(.AA(10), .BB(5), .CC(5))"
            push(@param_transmit_name, $1);
            my $tmp_number = $2;
            $tmp_number =~ s/^\s+//;
            $tmp_number =~ s/\s+$//;
            push(@param_transmit_number, $tmp_number);
        }
        else {                                                      # "#(10, 5, 5)"
            push(@param_transmit_name, $param_self_name[$num]);
            my $tmp_number = $tmp;
            $tmp_number =~ s/^\s+//;
            $tmp_number =~ s/\s+$//;
            push(@param_transmit_number, $tmp_number);
            $num++;
        }
    }
    if ($param_in =~ /\.(\w+)\s*?\(([\s|\S]*)\)/g) {                # "#(.AA(10))"
        push(@param_transmit_name, $1);
        my $tmp_number = $2;
        $tmp_number =~ s/^\s+//;
        $tmp_number =~ s/\s+$//;
        push(@param_transmit_number, $tmp_number);
    }
    elsif ($param_in =~ /\S/) {                                     # "#(10)"
        push(@param_transmit_name, $param_self_name[$num]);
        my $tmp_number = $param_in;
        $tmp_number =~ s/^\s+//;
        $tmp_number =~ s/\s+$//;
        push(@param_transmit_number, $tmp_number);
    }

    # change the original parameter value to the new value passed.
    for (my $i = 0 ; $i < @param_transmit_name ; $i ++) {
        for (my $j = 0 ; $j < @param_self_name ; $j ++) {
            if ($param_self_name[$j] eq $param_transmit_name[$i]) {
                $param_self_number[$j] = $param_transmit_number[$i];
            }
        }
    }

    # find localparam
    while ($lines =~ /localparam\s+([\s|\S]*?);/g) {
        my $tmp = $1;
        while ($tmp =~ /([\s|\S]*?),([\s|\S]*)/g) {                 # avoid "localparam AA = 2 , BB = 2'h1;"
            $tmp = $2;
            my $tmp_2 = $1;
            if ($tmp_2 =~ /(\w+)\s*?=\s*?(.*)/g) {
                push(@param_self_name, $1);
                my $tmp_number = $2;
                $tmp_number =~ s/^\s+//;
                $tmp_number =~ s/\s+$//;
                push(@param_self_number, $tmp_number);
            }
        }
        if ($tmp =~ /(\w+)\s*?=\s*?(.*)/g) {
            push(@param_self_name, $1);
            my $tmp_number = $2;
            $tmp_number =~ s/^\s+//;
            $tmp_number =~ s/\s+$//;
            push(@param_self_number, $tmp_number);
        }
    }

    @param_self_name = (@param_self_name, @param_common_name);
    @param_self_number = (@param_self_number, @param_common_number);

    for ( my $i = 0 ; $i < @param_self_name ; $i ++) {
        foreach $b (@file) {
            if ($b !~ /$param_self_name[$i]\s*?=/) {                # when not defined
                $b =~ s/\`?\b$param_self_name[$i]\b/$param_self_number[$i]/g;
            }
        }
    }

    return @file;
}

=head1     find reg signals in module
    @INPUT $name_inst, @file
    @return  NONE
        Find all regs, including single bit and multi bits.
        Write results such as "top.u_a.reg_a[1:0]" to <REGS_RESULT>.
=cut
sub find_signals {
    # Perl: When the scalar($) and array(@) parameters are passed in at the same time,
    # the scalar($) needs to be put the first.
    my ($name_inst_tmp, @file) = @_;

    my @regs_bit;
    my @regs_bits;
    my @regs_bits_high;
    my @regs_bits_low;

    ###### find all the defined regs ######
    # find "output reg [1:0] aa".
    foreach $a (@file) {
        if($a =~ /output\s+reg\s*?\[(.*?):(.*?)\]\s*?(\w+)/){
            my $bits_high = $1;
            my $bits_low = $2;
            my $bits = $3;
            push(@regs_bits_high, $bits_high);
            push(@regs_bits_low,  $bits_low);
            push(@regs_bits, $bits);
        }
        elsif ($a =~ /output\s+reg\s+(\w+)/) {
            my $bit = $1;
            push(@regs_bit, $bit);
        }
    }
    my $lines = join ('', @file);
    $lines =~ s/output\s+reg\s+/output /g;              # remove "output reg"

    # find common regs.
    # use "while ($lines)" instead of "foreach $a (@file)" to avoid cross line matching
    # like this :  reg [1:0] aa,
    #                        bb;
    while ($lines =~ /(\s+reg\s+[\s|\S]*?;)/g){
        my $regs_data = $1;
        if($regs_data =~ /\s+reg\s+\[(.*?):(.*?)\]\s+([\s|\S]*);/g){
            my $bits_high = $1;
            my $bits_low = $2;
            my $bits = $3;
            my $tmp;
            while ($bits =~ /([\s|\S]*),([\s|\S]*)/g) {
                $bits = $1;
                $tmp = $2;
                $tmp =~ s/^\s+//;                       # clear space
                $tmp =~ s/\s+$//;                       # clear space
                push(@regs_bits_high, $bits_high);
                push(@regs_bits_low,  $bits_low);
                push(@regs_bits, $tmp);
            }
            $bits =~ s/^\s+//;
            $bits =~ s/\s+$//;
            push(@regs_bits_high, $bits_high);
            push(@regs_bits_low,  $bits_low);
            push(@regs_bits, $bits);
        }
        elsif ($regs_data =~ /\s+reg\s+([\s|\S]*);/g) {
            my $bit = $1;
            my $tmp;
            while ($bit =~ /([\s|\S]*),([\s|\S]*)/g) {
                $bit = $1;
                $tmp = $2;
                $tmp =~ s/^\s+//;
                $tmp =~ s/\s+$//;
                push(@regs_bit, $tmp);
            }
            $bit =~ s/^\s+//;
            $bit =~ s/\s+$//;
            push(@regs_bit, $bit);
        }
    }

    my @regs_bit_real;
    my @regs_bits_real;
    my @regs_bits_high_real;
    my @regs_bits_low_real;

    my @regs_always;
    for (my $i = 0; $i < @file ; $i++){
        if($file[$i] =~ /always\s*@\s*\(.*?edge.*?\)/){
            @regs_always = (@regs_always, find_always($i, @file));
        }
    }
    #delete the repeated regs
    my %hash;
    @regs_always = grep {++$hash{$_}<2} @regs_always;

    foreach $a (@regs_bit) {
        if(grep { $a eq $_} @regs_always){
            push(@regs_bit_real, $a);
        }
    }
    for(my $i = 0 ; $i <= @regs_bits ; $i++) {
        if(grep { $regs_bits[$i] eq $_} @regs_always) {
            push(@regs_bits_high_real, $regs_bits_high[$i]);
            push(@regs_bits_low_real,  $regs_bits_low[$i]);
            push(@regs_bits_real, $regs_bits[$i]);
        }
    }

    for (my $k = 0 ; $k <= @regs_bit_real ; $k++) {
        if(defined($regs_bit_real[$k])) {
            print REGS_RESULT "$name_inst_tmp.$regs_bit_real[$k]\n";
        }
    }

    for (my $k = 0 ; $k <= @regs_bits_real ; $k++) {
        if(defined($regs_bits_real[$k])) {
            print REGS_RESULT "$name_inst_tmp.$regs_bits_real[$k]\[$regs_bits_high_real[$k]:$regs_bits_low_real[$k]\]\n";
        }
    }

}

=head1        find timing always block in module
    @INPUT  $num, @file
    @return @regs_always
        Find all regs in timing always@ block of module.
=cut
sub find_always {
    my ($num, @file) = @_;
    my $num_end = $num;

    my $num_end = $num+1;
    for($num_end ; $num_end < @file ; $num_end++) {
        if($file[$num_end] =~ /always\s*@\s*\(.*?\)/) {
            last;
        }
        elsif ($file[$num_end] =~ /assign\s+/) {
            last;
        }
        elsif ($file[$num_end] =~ /endmodule/) {
            last;
        }
    }

    my @regs_always;
    for(my $n = $num ; $n < $num_end ; $n++) {
        if ($file[$n] =~ /\s*(\w+)\s*<?\s*=/) {             # test_reg <= 0;
            push(@regs_always, $1);
        }
        elsif ($file[$n] =~ /\s*?\{(.*?)\}\s*<?\s*=/) {     # {test1, test2} <= 0;
            my $tmp = $1;
            while ($tmp =~ /([\s|\S]*),([\s|\S]*)/g) {
                $tmp = $1;
                my $tmp_2 = $2;
                $tmp_2 =~ s/^\s+//;
                $tmp_2 =~ s/\s+$//;
                push(@regs_always, $tmp_2);
            }
            $tmp =~ s/^\s+//;
            $tmp =~ s/\s+$//;
            push(@regs_always, $tmp);
        }
    }

    return @regs_always;
}