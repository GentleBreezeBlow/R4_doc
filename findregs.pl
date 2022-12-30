#!/usr/bin/perl
##################################################################################
# Author        : ylu
# Data          : 2022.12.30
# Revision      : 0.9
# Purpose       : Find all regs.
##################################################################################
#
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! Warning !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# !! *Please use standard verilog code.                                         !!
# !! *Not support SystemVerilog.                                                !!
# !! *Not support macros with the same name.                                    !!
# !!     e.g. `undef in Synopsys DW IP.                                         !!
# !! *Not support Very Complex situatiions.                                     !!
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! Warning !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#
###### updata log ######
# 22.12.13      identify modules and files, find out basic regs.
# 22.12.14      fix bug that can't identify parameterized instance module.
# 22.12.15      add identification macro defination code blocks.
# 22.12.17      add support parameterized regs.
# 22.12.18      add support parameters in the parameter  (e.g. parameter AA=BB+1;)
#               and bit width multiple addition and subtraction. (e.g. 1'b1-2+3'h7)
# 22.12.23      fix bug that identify macro code block.
# 22.12.23      add support internal macro definition in code.
# 22.12.29      add export the instantiation of modules containing regs.
# 22.12.30      fix bug that parameters convert to real number.



############################# read verilog filelist ##############################
print "Please input verilog filelist name:\n";
$verilog_files = "filelist.f";#<STDIN>;
chomp($verilog_files);
open (V_FILELIST, "<$verilog_files") or die "Can't open $verilog_files: $!";
@file_list = <V_FILELIST>;
close V_FILELIST;

print "Please input top module name:\n";
$top_module = "test_top";#<STDIN>;
chomp($top_module);

print "Please input top inst name:\n";
$name_inst = "dut";#<STDIN>;
chomp($name_inst);

print "Please input additional macrolist name:\n";
$macrolist_name = "macrolist.f";#<STDIN>;
chomp($macrolist_name);
open (MACRO_LIST, "<$macrolist_name") or die "Can't open $macrolist_name: $!";
@macro_list = <MACRO_LIST>;
close MACRO_LIST;

print "Please input first include file name:\n";
$first_include_file_name = "defs.v";#<STDIN>;
chomp($first_include_file_name);


################################# delete comments ################################
mkdir "no_comment_files";
open (V_FILELIST_NO_COMMENT, ">filelist_no_comment.f") or die "Can't write filelist_no_comment.f: $!";
foreach $a (@file_list) {
    open (FILE_TMP, "<$a") or die "Can't open $a: $!";
    my @vfile = <FILE_TMP>;
    close FILE_TMP;
    my $flag = 0;
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
    }

    $a =~ /(\w+)\.v/;
    my $file_name_no_comment = "no_comment_".$1.".v";
    print V_FILELIST_NO_COMMENT "./no_comment_files/$file_name_no_comment\n";
    open (NO_COMMENT_CODE, ">./no_comment_files/$file_name_no_comment") or die "Can't write $file_name_no_comment: $!";
    print NO_COMMENT_CODE @vfile;
    close NO_COMMENT_CODE;
}
close V_FILELIST_NO_COMMENT;

# open filelist no comment
open (V_FILELIST_NO_COMMENT, "<filelist_no_comment.f");
@file_list_no_comment = <V_FILELIST_NO_COMMENT>;
close V_FILELIST_NO_COMMENT;


############################# filter macro code block ############################
###### find out all macros ######
# find all verilog file with defining macro (e.g. `define TEST).
@filelist_define_macro;                    # file that use "`define" to define macro.
foreach $a (@file_list_no_comment) {

    open (DEFINE_TMP, "<$a") or die "Can't open $a: $!";
    my @vfile = <DEFINE_TMP>;
    close DEFINE_TMP;

    my $flag_define = 0;
    foreach $b (@vfile) {
        if ($b =~ /\`define\s+(\w+)\s*$/) {
            $flag_define = 1;
            last;
        }
    }
    if ($flag_define == 1) {
        push(@filelist_define_macro, $a);
    }
}

@filelist_include_macro;                    # file that use "`include" to get macro.
# find all macro in first include file.
foreach $a (@file_list_no_comment) {
    if ($a =~ /$first_include_file_name/) {
        my @vfile = clear_macro($a);

        push(@filelist_include_macro, $a);
        # push common macro.
        foreach $c (@vfile) {
            if ($c =~ /\`define\s+(\w+)\s*$/) {
                push(@macro_list, $1);
            }
        }
    }
}

# find all macro defined
find_include_macro($first_include_file_name);

# if macro definition does not apply `include.
foreach $a (@filelist_define_macro) {
    if(grep { $a eq $_} @filelist_include_macro) {
        next;
    }
    else {
        my @vfile = clear_macro($a);

        push(@filelist_include_macro, $a);
        # push common macro.
        foreach $c (@vfile) {
            if ($c =~ /\`define\s+(\w+)\s*$/) {
                push(@macro_list, $1);
            }
        }
    }
}

# delete macro code block without macro definition. 
mkdir "pure_files";
open (V_FILELIST_PURE, ">filelist_pure.f") or die "Can't write filelist_pure.f: $!";
foreach $a (@file_list_no_comment) {
    my @vfile = clear_macro($a);
    
    ###### delete blank lines ######
    my @vfile_real;
    foreach $a (@vfile) {
        if ($a =~ /\w|\(|\)/){
            push (@vfile_real, $a);
        }
    }

    $a =~ /no_comment_(\w+)\.v/;
    my $file_name_pure = "pure_".$1.".v";
    print V_FILELIST_PURE "./pure_files/$file_name_pure\n";
    open (PURE_CODE, ">./pure_files/$file_name_pure") or die "Can't write $file_name_pure: $!";
    print PURE_CODE @vfile_real;
    close PURE_CODE;
}
close V_FILELIST_PURE;

open (V_FILELIST_PURE, "<filelist_pure.f");
@file_list_pure = <V_FILELIST_PURE>;
close V_FILELIST_PURE;


############################# find common parameters #############################
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
        if($b =~ /\`define\s+(\w+)\s+([\s|\S]+)\s*\n?/){   
            my $name = $1;
            my $number = $2;
            if ($number =~ /\w/) {
                $number =~ s/^\s+//;
                $number =~ s/\s+$//;
                push(@param_common_name, $name);
                push(@param_common_number, $number);
            }
        }
    }
}

# The two global arrays @param_self_name_global and @param_self_number_global
# are used for recursive subfunction 'replace_param_in_param'.
@param_self_name_global;
@param_self_number_global;

# output common parameters to file.
@param_self_name_global = @param_common_name;
@param_self_number_global = @param_common_number;
for (my $i = 0 ; $i < @param_self_number_global ; $i ++) {
    $param_self_number_global[$i] = replace_param_in_param($param_self_number_global[$i]);
}
@param_common_name = @param_self_name_global;
@param_common_number = @param_self_number_global;
open (COMMON_PARAMS, ">common_params.data") or die "Can't write common_params.data: $!";
for (my $param_cnt = 0 ; $param_cnt < @param_common_name ; $param_cnt ++) {
    print COMMON_PARAMS $param_common_name[$param_cnt];
    print COMMON_PARAMS "\t\t$param_common_number[$param_cnt]\n";
}
close COMMON_PARAMS;


################################ find all modules ################################
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
            push(@module_file_result, "$1"."===>"."$filename");
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


###################### find reg/instantiation relationship #######################
open (REGS_RESULT, ">regs.data") or die "Can't write regs.data: $!";
open (INST_DATA, ">inst.data") or die "Can't write inst.data: $!";
open (INST_WITH_REGS_DATA, ">inst_with_regs.data") or die "Can't write inst_with_regs.data: $!";

# top module regs
my @file_top = find_module($top_module);
my ($file_noparam_top, $param_this_layer_name_top, $param_this_layer_number_top) 
   = replace_param('', \@file_top, \@param_common_name, \@param_common_number);
find_signals($name_inst, @{$file_noparam_top});
# instantiation relationship
find_inst(\@file_top, $param_this_layer_name_top, $param_this_layer_number_top);

close INST_DATA;
close REGS_RESULT;
close INST_WITH_REGS_DATA;



##################################################################################
#
#   sub functions
#
##################################################################################
=head1       find all macros defined
    @INPUT  $include_name
    @return NONE
        This can only find the macro defined in the file using {include "**.v"}.
            so please standardize the verilog code.
=cut
sub find_include_macro {
    my ($include_name) = @_;

    my @next_include_name;
    foreach $a (@filelist_define_macro) {
        open (DEFINE_TMP, "<$a") or die "Can't open $a: $!";
        my @vfile = <DEFINE_TMP>;
        close DEFINE_TMP;

        my $flag_include = 0;
        foreach $b (@vfile) {
            if ($b =~ /\`include\s+\"\s*$include_name\s*\"/) {
                $flag_include = 1;
                last;
            }
        }
        if ($flag_include == 1) {
            $a =~ /no_comment_(\w+)\.v/;
            push(@next_include_name, "$1".".v");
            push(@filelist_include_macro, $a);

            @vfile = clear_macro($a);
            # push common macro.
            foreach $c (@vfile) {
                if ($c =~ /\`define\s+(\w+)\s*$/) {
                    push(@macro_list, $1);
                }
            }
        }
    }

    foreach $a (@next_include_name) {
        find_include_macro($a);
    }
}

=head1       clear macro code block
    @INPUT  $file_name
    @return @file after clearing macro block
        find out the macro definition code.
=cut
sub clear_macro {
    my ($file_name) = @_;

    open (FILE_TMP, "<$file_name") or die "Can't open $file_name, $!";
    my @vfile = <FILE_TMP>;
    close FILE_TMP;

    my @macro_start_num;
    my @macro_end_num;

    ###### find macro code ######
    my $flag_macro = 0;                     # prevent macro code blocks including macro code blocks.
    for(my $i = 0; $i < @vfile ; $i++) {
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

    return @vfile;
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
                @macro_next = '';           # clear array
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
        if ($a =~ /$module_name===>(.*).v/) {
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
        if($a =~ /module\s+$module_name/) {
            $flag = 1;
        }
        if($a =~ /endmodule/) {
            if ($flag == 1) {
                push(@file_real, $a);
            }
            $flag = 0;
        }
        if($flag == 1) {
            push(@file_real, $a);
        }
    }

    return @file_real;
}

=head1      find instantiation relationship
    @INPUT  \@file_in, \@param_last_layer_name, \@param_last_layer_number
    @return NONE
        Use the recursion idea to find the deepest instantiation module.
        when the "for" and "foreach" loop recurses to the deepest layer,
            the module is no longer contains instantiation module.
        @param_this_layer_name, @param_this_layer_number, 
        @param_last_layer_name, @param_last_layer_number, 
            these variables are used to avoid one situation: "#(.AA(BB))"
            the parameters passed in the instantiation module are not numbers
            but parameters from last layer. 
            This may set multiple layers of parameters.
=cut
sub find_inst {
    my ($file_in, $param_last_layer_name, $param_last_layer_number) = @_;
    my @file = @{$file_in};
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
                    my ($file_real_noparam, $param_this_layer_name, $param_this_layer_number) 
                         = replace_param($param_in, \@file_real, $param_last_layer_name, $param_last_layer_number);
                    find_signals($name_inst, @{$file_real_noparam});
                    find_inst(\@file_real, $param_this_layer_name, $param_this_layer_number);
                    $name_inst = $name_inst_tmp;
                }
            }
        }
    }
}

=head1     replace parameters with numbers.
    @INPUT  $param_in, \@file, \@param_last_layer_name, \@param_last_layer_number
    @return \@file after replacing, \@param_self_name(this layer), \@param_self_number(this layer)
=cut
sub replace_param {
    my ($param_in, $file_in, $param_last_layer_name_in, $param_last_layer_number_in) = @_;
    my @file = @{$file_in};
    my @param_last_layer_name = @{$param_last_layer_name_in};
    my @param_last_layer_number = @{$param_last_layer_number_in};

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

    # If parameters passed in are the parameters of the previous layer.
    for (my $i = 0 ; $i < @param_transmit_number ; $i ++) {
        if ($param_transmit_number[$i] !~ /\d/) {                   # "#(.AA(BB))"
            for (my $j = 0 ; $j < @param_last_layer_name ; $j ++) {
                if ($param_transmit_number[$i] eq $param_last_layer_name[$j]) {
                    $param_transmit_number[$i] = $param_last_layer_number[$j];
                }
            }
        }
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

    # assign the parameters of current module to the global array 
    # @param_self_name_global and @param_self_number_global, so that 
    # recursive subfunction 'replace_param_in_param' can be used.
    @param_self_name_global = @param_self_name;
    @param_self_number_global = @param_self_number;
    for (my $i = 0 ; $i < @param_self_number_global ; $i ++) {
        $param_self_number_global[$i] = replace_param_in_param($param_self_number_global[$i]);
    }
    # reassign the processed global array to the self array.
    @param_self_name = @param_self_name_global;
    @param_self_number = @param_self_number_global;

    for ( my $i = 0 ; $i < @param_self_name ; $i ++) {
        foreach $b (@file) {
            if ($b !~ /$param_self_name[$i]\s*?=/) {                # when not defined
                my $tmp_change = $param_self_number[$i];
                $tmp_change =~ s/^\s+//;
                $tmp_change =~ s/\s+$//;
                $b =~ s/\`?\b$param_self_name[$i]\b/\($tmp_change\)/g;  # () used to give priority to operations
            }
        }
    }

    return (\@file, \@param_self_name, \@param_self_number);
}

=head1      Replace parameters in parameters
    @INPUT  the parameter
    @return the parameter after replacing
        Recursive subfunction to avoid this situation :
        # `define AA 1                  # `define AA 1
        # `define BB `AA+1              # parameter BB = `AA + 1
        # `define CC `BB+1              # parameter CC =  BB+1
        etc.
=cut
sub replace_param_in_param {
    my ($tmp_param_number) = @_;

    for (my $j = 0 ; $j < @param_self_name_global ; $j ++) {
        if ($tmp_param_number =~ /\b$param_self_name_global[$j]\b/){
            my $tmp_number = $param_self_number_global[$j];
            $tmp_number =~ s/^\s+//;
            $tmp_number =~ s/\s+$//;
            $tmp_param_number =~ s/\`?\b$param_self_name_global[$j]\b/\($tmp_number\)/g;    # () used to give priority to operations
        }
    }

    for (my $j = 0 ; $j < @param_self_name_global ; $j ++) {
        if ($tmp_param_number =~ /\b$param_self_name_global[$j]\b/) {
            $tmp_param_number = replace_param_in_param($tmp_param_number);
        }
    }

    return $tmp_param_number;
}

=head1     find reg signals in module
    @INPUT  $name_inst, @file
    @return NONE
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

    # find common defined regs.
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
            while ($bits =~ /([\s|\S]*?),([\s|\S]*)/g) {
                $bits = $2;
                $tmp = $1;
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
            while ($bit =~ /([\s|\S]*?),([\s|\S]*)/g) {
                $bit = $2;
                $tmp = $1;
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

    # store the real registers. 
    # register must appear in the timing always block.
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

    # convert to real number
    # e.g. "[5-1:0]", "[5 - 1 + 21:0]", "[3'h7:1'b0]", "[2'b11 - 1:0]" etc.
    foreach $a (@regs_bits_high_real) {
        #$a =~ s/\s*?[0]*(\w+)\s*?/$1/g;                        # if "0011 + 1", then "11+1". avoid being mistaken for octal.
        $a =~ s/\d*?\'(h|H)\s*?(\w+)\s*?/0x$2/g;                # hexadecimal
        $a =~ s/\d*?\'(h|H)\s*?\(\s*?(\w+)\s*?\)\s*?/0x$2/g;
        $a =~ s/\d*?\'(b|B)\s*?(\w+)\s*?/0b$2/g;                # binary
        $a =~ s/\d*?\'(b|B)\s*?\(\s*?(\w+)\s*?\)\s*?/0b$2/g;    
        $a =~ s/\d*?\'(o|O)\s*?(\w+)\s*?/0$2/g;                 # octal
        $a =~ s/\d*?\'(o|O)\s*?\(\s*?(\w+)\s*?\)\s*?/0$2/g;
        $a =~ s/\d*?\'(d|D)\s*?[0]*(\w+)\s*?/$2/g;              # decimal
        $a =~ s/\d*?\'(d|D)\s*?\(\s*?[0]*(\w+)\s*?\)\s*?/$2/g;

        $a = eval($a);

    }
    foreach $a (@regs_bits_low_real) {
        #$a =~ s/\s*?[0]*(\w+)\s*?/$1/g;                        # if "0011 + 1", then "11+1". avoid being mistaken for octal.
        $a =~ s/\d*?\'(h|H)\s*?(\w+)\s*?/0x$2/g;                # hexadecimal
        $a =~ s/\d*?\'(h|H)\s*?\(\s*?(\w+)\s*?\)\s*?/0x$2/g;
        $a =~ s/\d*?\'(b|B)\s*?(\w+)\s*?/0b$2/g;                # binary
        $a =~ s/\d*?\'(b|B)\s*?\(\s*?(\w+)\s*?\)\s*?/0b$2/g;    
        $a =~ s/\d*?\'(o|O)\s*?(\w+)\s*?/0$2/g;                 # octal
        $a =~ s/\d*?\'(o|O)\s*?\(\s*?(\w+)\s*?\)\s*?/0$2/g;
        $a =~ s/\d*?\'(d|D)\s*?[0]*(\w+)\s*?/$2/g;              # decimal
        $a =~ s/\d*?\'(d|D)\s*?\(\s*?[0]*(\w+)\s*?\)\s*?/$2/g;

        $a = eval($a);
    }

    # output result
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

    if ((@regs_bit_real) || (@regs_bits_real)) {
        print INST_WITH_REGS_DATA "$name_inst_tmp\n";
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
    
    my $lines = join ('', @file[$num...$num_end]);
    while ($lines =~ /\s*(\w+)\s*?<?\s*=/g) {               # test_reg <= 0;
        push(@regs_always, $1);
    }
    while ($lines =~ /\s*?\{([\s|\S]*?)\}\s*<?\s*=/g) {     # {test1, test2} <= 0;
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

    return @regs_always;
}