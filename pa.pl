#!/usr/bin/perl -w
=pod SYNOPSIS

    A perl script designed to make PATH managment easier (on win32 plateforms).

=cut
use 5.10.1;
use strict;
use warnings;
use File::Basename;
use File::Glob qw( bsd_glob );
use Getopt::Long::Descriptive;
use Win32;
use Win32API::Registry qw(:ALL);
our $VERSION = 0.03;
use constant DEBUG => 0;
use experimental 'smartmatch';
my ($opt, $usage);
my @path;
#A copy of initial @path array in order to retrieve original indexed path entries
# when invoked by index multiple times with modifiers commands such as 'top' and 'bottom'.
my @ori_path;
my $THIS_PATH;      #the script folder
my @MACHINE_PATH;   #read from registry
my @USER_PATH;      #
my %machine;
my %user;
my ($original_machine_path, $original_user_path);

main();
#-----------------------------------------------------------------------------------------------
sub main{
    #prepare $opt, $usage, $THIS_PATH, @path and @ori_path variables
    initialize();

    about()      if $opt->about;
    version()    if $opt->version;
    help()       if $opt->help;
    
    my $save = 0;
    my $cmd  = 0;
    
    if($opt->check){
        check_path();
        $cmd++;
    }

    if($opt->optimize){
        optimize();
        $save++;
    }

    if($opt->top){
        top();
        $save++;
    }

    if($opt->bottom or $opt->add){
        bottom();
        $save++;
    }

    if($opt->delete){
        _delete();
        $save++;
    }

    if($opt->listconf){
        listconf();
        $cmd++;
    }
    
    if($opt->saveconf){
        saveconf();
        $cmd++;
    }
    
    if($opt->loadconf){
        loadconf();
        $save++;
    }
    
    if($opt->delconf){
        delconf();
        $cmd++;
    }
    if($opt->which){
        which();
        $cmd++;
    }
    save_path() if $save;

    display_path() if $save+$cmd == 0 or defined $opt->show;

    exit;
}
#-----------------------------------------------------------------------------------------------

sub initialize{
    $THIS_PATH = get_script_path();
    
    ($opt, $usage) = do{ describe_options(
        'Usage: %c %o',
        [ 'top|t=s@',    "add/move given path(s) to the top of the PATH" ],
        [ 'bottom|b=s@', "add/move given path(s) to the bottom of the PATH" ],
        [ 'add|a=s@',    "alias for --bottom" ],
        [ 'delete|d=s@', "remove given path(s) from the PATH" ],
        [ 'show|s:s@',   "display PATH entries (default when no arguments)"],
        [ 'sort|S',      "sort entries alphanumericaly and append a real order column"],
        [ 'which|w=s',   "find a file in all path entries (wilcard allowed)"],
        [ 'update|u',  "update registry (USER, MACHINE)" ],
        [],         
        [ 'saveconf=s',  "save current path under an configuration name"],              
        [ 'loadconf=s',  "load configuration by name"],              
        [ 'delconf=s',   "delete configuration by name"],              
        [ 'listconf|l',  "display available configurations (try with --verbose)"],              
        [],               
        [ 'long|L',      "display long path name" ],
        [ 'verbose|v',   "make output more verbose" ],
        [ 'check|c',     "check path" ],
        [ 'optimize|o',  "optimize path (remove duplicate, inexistant and shorten paths)" ],
        [ 'about|A',     "output information about program" ],
        [ 'version|V',   "output version information" ],
        [ 'help|h',      "print full usage message and exit (try with --verbose)" ],
    ) };
    
    @path     = split_path( $ENV{PATH} );
    @ori_path = split_path( $ENV{PATH} );

    my ($key,$type);
    RegOpenKeyEx( HKEY_LOCAL_MACHINE, 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment', 0, KEY_READ, $key );
    RegQueryValueEx( $key, "Path", [], $type, $original_machine_path, [] );
    RegCloseKey( $key );
    RegOpenKeyEx( HKEY_CURRENT_USER, 'Environment', 0, KEY_READ, $key );
    RegQueryValueEx( $key, "PATH", [], $type, $original_user_path, [] );
    RegCloseKey( $key );
    
    @MACHINE_PATH = split_path( $original_machine_path );
    @USER_PATH    = split_path( $original_user_path    );
    %machine      = map { $_->[2], $_} @MACHINE_PATH;
    %user         = map { $_->[2], $_} @USER_PATH;

}

sub split_path{
    my $flat_path = shift;
    my $order = 1;
    my @local_path;
    foreach my $pa ( split ';', $flat_path ){
        my $key = mk_uniq( $pa );
        push @local_path, [ $order, $pa, $key ];
        $order ++;
    }
    return @local_path;
}

sub about{
    say "$0 is an utility that help to manage PATH entries from command line.";
    say "";
}
    
sub version{
    say "Version: $VERSION";
    say "";
}

sub help{
    if($opt->verbose){
        about()   unless $opt->about;
        version() unless $opt->version;
    }
    say $usage->text;
    if($opt->verbose){
        say <<'ADDITIONAL';
Entries can be specified by 
    path        e.g.: --top c:\dev\perl\bin
    :index      e.g.: --top :-1 --bottom :42
    :index..n   e.g.: --top :4..8
    /regex/     e.g.: --top /perl/
    !/regex/    e.g.: --top !/perl/	(negate matches)
ADDITIONAL

        say <<'ADDITIONAL';
Usages:
    To move last entry on the top and display what was done:
        pa --top :-1 --verbose
    or  pa -vt:-1f
    To delete entries of indexed between 4 and 8:
        pa --delete :4..8
    or  pa -d:4..8
    To show 4 last entries:
        pa --show :-1..-4
    To move at the bottom all entries that match regex /python/ :
        pa --bottom /python/
    To list available configurations with there content:
        pa --listconf --verbose
    To save current PATH into configuration 'conf1'
        pa --saveconf conf1
    To load configuration 'conf1'
        pa --loadconf conf1
    To delete configuration 'conf1'
        pa --delconf conf1
    To find all perl dll in path:
        pa --which perl*.dll
    or  pa -wperl*.dll
    To check for path entries
        pa --check
ADDITIONAL
    }
    exit;
}

sub dump_path{
    my $pa = shift;
    my $size = length scalar @path; #how many chars needed to write last index ?
    my $m = exists $machine{$pa->[2]} ? 'M' : '-';
    my $u = exists    $user{$pa->[2]} ? 'U' : '-';
    my $path = $opt->long ? Win32::GetLongPathName( $pa->[1] )//$pa->[1] : $pa->[1];
    return sprintf "%s%s %*i) %s", $m, $u, $size, $pa->[0], $path;
}

sub check_path{
    my $msg = 0;
    #check for duplicates
    my %uniq;
    my $i = 1;
    foreach my $pa ( @path ){
        my $pa_uq = $pa->[2];
        push @{$uniq{$pa_uq}}, $pa;
        $i++;
    }
    #check for invalid path entries (no duplicates, so use first of list)
    foreach my $palist ( values %uniq ){
        my $pa = $palist->[0];
        unless(-d $pa->[1]){
            my $m = exists $machine{$pa->[2]} ? 'M' : '-';
            my $u = exists    $user{$pa->[2]} ? 'U' : '-';
            say "\tEntry does not exists: $m$u $pa->[0]) '$pa->[1]'";
            $msg++;
        }
    }
    
    #remove non duplicated
    foreach my $key (keys %uniq ){
        delete $uniq{$key} unless @{$uniq{$key}} > 1;
    }
    
    if(keys %uniq){
        $msg++;
        say "Duplicated entries:";
        foreach my $key ( keys %uniq ){
            say "\tPointing to $key:";
            foreach my $pa ( @{$uniq{$key}} ){
                say "\t\t", dump_path($pa);
            }
        }
    }
    
    say "Nothing strange in your path." unless $msg;
}

# look for meta characters that allows to match multiple entries at once
# such as regex or index range.
# always works with @ori_path
sub expand_meta{
    my $pa = shift;
    my @entries;
    if($pa =~ /^:(-?\d+)(?:\.\.(-?\d+))?$/){
        my ($index, $index2) = ($1, $2);
        $index2 //= $index;
        $index2 -- unless $index2 < 1;
        $index -- unless $index < 1;
        #check for array ranges (and accept negativ numbers which is perlish :-))
        ($index,$index2)=($index2,$index) if $index > $index2;
        foreach my $i ($index..$index2){
            push @entries, $ori_path[$i];
        }
    }
    elsif($pa =~ /^:?(!?)\/(.*)\/$/){
        my ($type, $pattern) = ($1, $2);
        #scan for regexs and append matching entries from @ori_path
        ENTRY:
        foreach my $pa ( @ori_path ){
            if($type eq ''){
                next ENTRY unless $pa->[1] =~ /$pattern/i or $pa->[2] =~ /$pattern/i;
            }
            else{
                next ENTRY unless $pa->[1] !~ /$pattern/i and $pa->[2] !~ /$pattern/i;
            }
            push @entries, $pa;
        }
    }
    else{
        #@ori_path or @path ?
        #Should use an optional arg to switch array ?
        my $pa_uq = mk_uniq($pa);
        push @entries, grep { $_->[1] eq $pa_uq or $_->[2] eq $pa_uq } @path; 
    }
    return @entries;
}

sub mk_uniq{
    my $pa = shift;
    my $new_pa = Win32::ExpandEnvironmentStrings( $pa );
    $new_pa =~ s/"//g;
    $new_pa =~ s{/|\\{2,}}{\\}g;
    $new_pa =~ s/\\$//g;
    $new_pa = Win32::GetLongPathName( $new_pa ) // $new_pa;
    $new_pa = Win32::GetFullPathName( $new_pa ) // $new_pa;
    $new_pa = lc $new_pa;
    say "mk_uniq('$pa') => '$new_pa'" if DEBUG;
    return $new_pa;
}

#Sort entries
sub sentries{ lc $a->[1] cmp lc $b->[1] }

#The path array to be used is the @path which allow to display modified path list
#when called with modifier commands such as top/bottom/delete/add
#But indexes MUST be resolved using the @ori_path
sub display_path{
    my $count = scalar @path;
    my $size = length $count;
    my @entries = @path;
    my @show = @{ $opt->show // [] };
    #~ use Data::Show; show( \@show );
    @show = () if @show ~~ ['']; #user don't want that (eg. --show), he want to see all entries
    @entries = map{ expand_meta($_) } @show if @show;
    @entries = sort sentries @entries if $opt->sort;
        
    foreach my $pa ( @entries ){
        say dump_path( $pa );
    }
    say "You have $count path entries" if $opt->verbose;
}

sub extract_entries{
    my @byIndex;
    my @entries = map{ expand_meta $_ } @_;
    foreach my $entry ( @entries ){
        $byIndex[ $entry->[0] ]=1;
    }
    #remove entries to be extracted
    @path = grep { not $byIndex[ $_->[0] ] } @path;
    return @entries;
}

sub top{
    #remove entries wich match with given path in $opt->top and put a new entry at the top
    my @entries = extract_entries( @{ $opt->top } );
    #print verbose info if required
    if($opt->verbose){
        foreach my $entry( @entries ){
            say "moving to top: $entry->[1]";
        }
    }
    #move on the top
    unshift @path, @entries;
    #rebuild indexes for sorted operation
    rebuild_entries();
}

sub bottom{
    #remove entries wich match with given path in $opt->bottom and put a new entry at the bottom
    my @entries = extract_entries( 	@{ $opt->bottom // [] }, 
                                    @{ $opt->add // []    } );
    #print verbose info if required
    if($opt->verbose){
        foreach my $entry( @entries ){
            say "moving to bottom: $entry->[1]";
        }
    }
    #move on the bottom
    push @path, @entries;
    #rebuild indexes for sorted operation
    rebuild_entries();
}

sub _delete{
    #remove entries wich match with given path in $opt->delete
    my @entries = extract_entries( @{ $opt->delete } );
    #print verbose info if required
    if($opt->verbose){
        say "deleting: ", dump_path($_) for @entries;
    }
    #rebuild indexes for sorted operation
    rebuild_entries();
}

sub rebuild_entries{
    my $i = 1;
    $_->[0] = $i++ for @path;
}

sub save_path{
    my $path = join ';', map{ $_->[1] } @path;
    setenv( 'PATH', $path );
    if($opt->update){
        #rebuild USER and MACHINE paths then update registry keys
        my $user_path    = join ';', map{ $_->[1] } grep{ exists    $user{$_->[2]}    } @path;
        my $machine_path = join ';', map{ $_->[1] } grep{ exists    $machine{$_->[2]} } @path;
        my $key;
        my $type = REG_SZ;
        if($original_user_path ne $user_path){
            if(RegOpenKeyEx( HKEY_CURRENT_USER, 
                            'Environment', 0, KEY_SET_VALUE, $key )){
                RegSetValueEx( $key, "Path", 0, $type, $user_path ) 
                    or say "* ERROR setting USER registry PATH: $^E";
                say "USER registry path updated." if $opt->verbose;
                RegCloseKey( $key );
            }
            else{
                say STDERR "USER path not updated: $^E";
            }
        }
        
        if($original_machine_path ne $machine_path){
            if(RegOpenKeyEx( HKEY_LOCAL_MACHINE, 
                            'SYSTEM\CurrentControlSet\Control\Session Manager\Environment', 0, KEY_SET_VALUE, $key )){
                RegSetValueEx( $key, "PATH", 0, $type, $machine_path ) 
                    or say "* ERROR setting MACHINE registry PATH: $^E";
                say "MACHINE registry path updated." ;
                RegCloseKey( $key );
            }
            else{
                say STDERR "MACHINE path not updated: $^E";
            }
        }
    }
}

sub setenv{
    my ($name, $value) = @_;
    if(($ENV{$name}//'') ne $value){
        my $filename = $ENV{PA_SHARED_CMD};
        open my $FH, '>', $filename or die "Could not open $filename for writting!";
        #TODO/maybe: enquote ^ and % in $value ?
        say $FH 'SET ', $name, '=', $value;
        say $FH "echo $name has been modified";
        close $FH;
        say "** PA_SHARED_CMD = '$filename' **" if DEBUG;
    }
    else{
        say "$name was not modified." if $opt->verbose;
    }
}

sub get_script_path{
    my $path=__FILE__;
    $path =~ s!\\!/!g;
    $path =~ s!/{2,}!/!g;
    $path =~ s!/[^/]*$!!;
    return $path;
}

sub readconf{
    my $file = shift;
    open my $FH, '<', $file or die "Could not load configuration '$file' : $!";
    my $index = 1;
    #TODO: make processing of disabled columns ?
    my @entries = map { chomp; [ $index++, $_, mk_uniq($_) ] } <$FH>;
    close $FH;
    return @entries;
}

sub listconf{
    my $configs = 0;
    foreach my $conf ( sort ( bsd_glob( "$THIS_PATH/configs/*" ) ) ){
        $configs++;
        my $confname = basename( $conf );
        say "[$confname]";
        if($opt->verbose){
            my @entries = readconf( $conf );
            #Take in account "--sort" option
            @entries = sort sentries @entries if $opt->sort;
            my $size = length scalar @entries;
            foreach my $entry ( @entries ){
                say dump_path($entry);
            }
        }
    }
    say "no configurations." unless $configs;
}

sub loadconf{
    my $file = "$THIS_PATH/configs/" . $opt->loadconf;
    die "No configuration '", $opt->loadconf, "!'" unless -e $file;
    #set @path
    @path = readconf( $file );
    #rebuild path
    save_path();
    say "Configuration '",$opt->loadconf,"' loaded." if $opt->verbose;	
}

sub delconf{
    my $file = "$THIS_PATH/configs/" . $opt->delconf;
    die "No configuration '", $opt->delconf, "'!" unless -e $file;
    unlink $file or die "Could not delete configuration '$file' : $!";
    say "Configuration '",$opt->delconf,"' deleted." if $opt->verbose;
}

sub saveconf{
    #create folder if doesn't exist
    mkdir "$THIS_PATH/configs" 
        or die "could not create directory '$THIS_PATH/configs' : $!"
        unless -d "$THIS_PATH/configs";
    my $file = "$THIS_PATH/configs/" . $opt->saveconf;
    #write path entries to file
    open my $FH, '>', $file or die "Could not write to file '$file' : $!";
    foreach my $pa ( @path ){
        #TODO: append a disabled column with * when disabled
        #~ say $FH $pa->[3], "\t", $pa->[1]; 
        say $FH $pa->[1]; 
    }
    close $FH;
    say "Configuration '",$opt->saveconf,"' saved." if $opt->verbose;
}
sub which{
    my $file = $opt->which;
    #TODO: add --useconf confname to work with a configuration
    #TODO: if not extension look for PATHEXT or allow wilcard
    #allow wilcard search with bsd_glob( ) in place of -e
    my @entries = @path;
    @entries    = sort sentries @entries if $opt->sort;
    my $count   = 0;
    my $wilcard = $file =~ /[?*]/;
    ENTRY:
    foreach my $entry ( @entries ){
        my $path = $entry->[1];
        $path =~ s/^"(.*)"$/$1/;#remove surrounding quottes
        $path =~ s![/\\]+$!!;#remove trailing path separator
        my @matches=();
        if($wilcard){
            @matches = bsd_glob( $path.'/'.$file );
            next ENTRY unless @matches;
        }
        else{
            next ENTRY unless -e $path.'/'.$file;
        }
        say dump_path( $entry );
        $count++;
        if($wilcard){
            for(@matches){
                s!/!\\!g;
                s!\\{2,}!\\!g;
                s!\\$!!g;
                if($opt->long){
                    $_ = Win32::GetLongPathName($_) // $_;
                    $_ = Win32::GetFullPathName($_) // $_;
                }
                say "\t\t", $_;
            }
        }
    }
    say "file not found!" unless $count;
}


sub optimize{
    #remove duplicate and inexistant paths
    my %uniq;
    #~ @pa = grep { -e $_->[2] and !$uniq{$_->[2]}++ } @pa;
    my @new_pa;
    PATH:
    for(@path){
        unless(-e $_->[1]){
            say "remove inexistant path: ", dump_path($_) if $opt->verbose;
            next PATH;
        }
        if($uniq{$_->[2]}++){
            say "remove duplacted entry: ", dump_path($_) if $opt->verbose;
            next PATH;
        }
        push @new_pa, $_;
    }
    @path = @new_pa;
    #reduce path size using Win32::GetShortPathName( $pa )
    $_->[1] = Win32::GetShortPathName( $_->[1] ) for @path;
    my $before = length $ENV{PATH};
    my $after = length join ';', map{ $_->[1] } @path;
    my $delta = ($before - $after);
    say "$delta chars saved." if $delta>1;
    say "1 char saved." if $delta==1;
    say "No chars saved." if $delta==0;
    say "Sorry I have wasted ",abs($delta)," chars: please report an issue." if $delta<0;    
}