#!/usr/bin/perl

use warnings;
use strict;
sub POE::Kernel::ASSERT_DEFAULT () { 1 }
sub POE::Kernel::ASSERT_EVENTS  () { 1 }
sub POE::Kernel::ASSERT_FILES   () { 1 }
use POE;
use FindBin;
use Proc::Daemon;
my $root = "$FindBin::Bin/../";
use lib "$FindBin::Bin/../extlib";

my $config = {
    debug       => 1,
	verbose	    => 1,
	name	    => 'main',
    daemonize   => 0,
    # log_file    => './data/serial2mqtt.log',
    log_file    => '-',
    log_fh      => undef,
    # config_file => 'conf/serial2mqtt.yaml',
	# Proc::Daemon
    work_dir	=> $root,
    setuid  	=> 'dst', # Sets the real user identifier ($<) and the effective user identifier ($>) for the daemon process using
    setgid  	=> 'dst dialout', # Sets the real group identifier ($() and the effective group identifier ($)) for the daemon process using
#     child_STDIN
#     child_STDOUT
#     child_STDERR
#     dont_close_fh
#     dont_close_fd
    pid_file	=> 'data/serial2mqtt.pid',
    # file_umask
    # exec_command

	stats	=> {
		enable	                => 1,
		name	                => 'stats',
		every	                => 60*5,
		every_callback	        => {
			session		        => 'main',
			event		        => 'ev_got_stats',
		},
	},
	serial	=> {
		enable	                => 1,
		name	                => 'serial',
		# port	                => '/dev/ttyUSB0',
		port	                => '/dev/serial_wde',
        baudrate                => 9600,
        datatype                => 'raw',
        databits                => 8,
        parity                  => 'none',
        stopbits                => 1,
        handshake               => 'none',
        restart_on_error_delay  => 20,
		input_callback	        => {
			session		        => 'main',
			event		        => 'ev_got_input',
		},
	},
    mqtt    => {
		enable	                => 1,
		name	                => 'mqtt',
        broker                  => '192.168.2.2',
        topic                   => '/custom/sensor1',
		retain	                => 1,
    },
    file    => {
		enable	                => 0,
		name	                => 'file',
        path	                => 'data/serial_input.txt',
        # path	                => '-',
		input_callback	        => {
			session		        => 'main',
			event		        => 'ev_got_input',
		},
    },
};

use Getopt::Long;
my $args;
Getopt::Long::GetOptions(
    'config-file|c=s'   => \$args->{config_file},
    'log-file|l=s'      => \$args->{log_file},
    'daemonize|D'       => \$args->{daemonize},
    'help|h'            => \$args->{help}
);

if ($args->{help}) {
    print STDERR << "EOT";
usage: $0
    -c, --config-file=file      config file to use (default: $config->{config_file})
    -l, --log-file=file         log file           (default: $config->{log_file})
    -D, --daemonize             run in background  (default: no)
    -h, --help                  this help
EOT
    exit 0;
}

# merge default config with config file from command line (if given)
if ($args->{config_file}) {
    use JSON;
    my $j = JSON->new();
    # qualify relative paths
    for (qw(config_file)) {
        if ((exists  $args->{$_}) and
            (defined $args->{$_}) and
            ($args->{$_} !~ m|^/|) and ($args->{$_} ne '-'))
        {
             $args->{$_} = sprintf('%s/%s', $root, $args->{$_});
        }
    }
    eval {
        local *F;
        open F, '<', $args->{config_file} or die "can't read config file:$args->{config_file} ($!)";
        # slurp and decode json config
        local $/ = undef;
        $config = $j->decode(<F>);
    }; if ($@) { die($@) }
}

# merge config with arguments from command line (if given)
if ($args->{log_file})  { $config->{log_file}  = $args->{log_file}  }
if ($args->{daemonize}) { $config->{daemonize} = $args->{daemonize} }

# qualify relative paths
for (qw(log_file config_file pid_file)) {
    if ((exists  $config->{$_}) and
        (defined $config->{$_}) and
        ($config->{$_} !~ m|^/|) and ($config->{$_} ne '-'))
    {
         $config->{$_} = sprintf('%s/%s', $root, $config->{$_});
         # main::verbose(sprintf('normalized %s:%s', $_, $config->{$_}));
         # print STDERR sprintf('normalized %s:%s'."\n", $_, $config->{$_});
    }
}

# use JSON; my $j = JSON->new();
# print $j->pretty->encode($config);
# exit 0;

$config->{log_fh} = open_log($config->{log_file});

if ($config->{daemonize}) {
    my $args = {
        work_dir     => $config->{work_dir},
        # child_STDOUT => '/path/to/daemon/output.file',
        child_STDOUT => sprintf('+>>%s', $config->{log_file}),
        child_STDERR => sprintf('+>>%s', $config->{log_file}),
        pid_file     => $config->{pid_file},
        # exec_command => 'perl /home/my_script.pl',
        # XXX open serial port in parent process?
        dont_close_fh => [ $config->{log_fh} ],
    };
    if (defined $config->{setuid}) { $args->{setuid} = $config->{setuid} };
    if (defined $config->{setgid}) { $args->{setgid} = $config->{setgid} };
    my $daemon = Proc::Daemon->new(%$args);

    my $pid = $daemon->Init();
    if ($pid){ print STDERR "child started with pid:$pid\n";  exit 0 };

    # child
    $poe_kernel->has_forked;
    main::verbose(sprintf('log_file:%s pid_file:%s pid:%s', $config->{log_file}, $config->{pid_file}, $$));
} else {
    main::verbose("Before: RUID=$<, EUID=$>, RGID=$(, EGID=$), umask=" .sprintf("%o",umask));
    if (defined $config->{setgid}) {
        my @gids;
        main::verbose(sprintf('setting groups:(%s)', $config->{setgid}));
        for (split /[ ,]/, $config->{setgid}) {
            my ($_name, $_passwd, $_gid, $_members) = getgrnam $_
                or die ("can't get gid from setgid:$_ ($config->{setgid}) ($!)");
            main::verbose(sprintf('setting group:(%s) name:%s passwd:%s gid:%s members:%s', $_, $_name, $_passwd, $_gid, $_members));
            push @gids, $_gid;
        }
        # (
        $) = (join ' ', @gids);
        main::verbose(sprintf('running as groups:(%s) gids in:(%s) gids out:(%s)', $config->{setgid}, (join ' ', @gids), "$)"));
    }
    if (defined $config->{setuid}) {
        my $uid = getpwnam($config->{setuid})
            or die ("can't get uid from setuid:$config->{setuid} ($!)");
        $> = $uid;
        main::verbose(sprintf('running as user:%s uid:%s', $config->{setuid}, $>));
    }
    main::verbose("After: RUID=$<, EUID=$>, RGID=$(, EGID=$), umask=" .sprintf("%o",umask));
}

my $wde = wde::main->new( $config );
POE::Kernel->run();
exit 0;

sub open_log {
    my ($file) = @_;
    if ($file eq '-') {
        return *STDERR;
    } else {
        # local *F;
        eval {
            open F, '>', $file or do {
                my $e = @_;  chomp $e;
                die("Can't write to log_file:$file ($e)\n");
            };
            select F; $| = 1; # make unbuffered
        };
        return *F
    }
}

sub debug {
    my $t = scalar localtime;
    $config->{debug} && $config->{log_fh}->print("[DBG][$t] @_\n");
}

sub verbose {
    my $t = scalar localtime;
    $config->{verbose} && $config->{log_fh}->print("[VER][$t] @_\n");
}

exit 0;
##############################################################

package wde::generic;
use warnings;
use strict;
use POE;

sub new {
	my ($class, $args) = @_;
    $args->{name} //= __PACKAGE__;
    return bless $args, $class;
}

sub ev_default {
    my ($self, $kernel, $event, $args) = @_[OBJECT, KERNEL, ARG0, ARG1];
    $self->debug(sprintf('[ev_default] event:%s args:(%s)', $event, (defined $args ? "@$args" : '')));
}

sub ev_child {
    my ($self, $kernel) = @_[OBJECT, KERNEL];
    # $self->verbose('[ev_child]');
}

sub debug {
    my ($self, $string) = @_;
    $self->{debug} && main::debug(sprintf('[%s] %s', $self->{name}, $string));
}

sub verbose {
    my ($self, $string) = @_;
    $self->{verbose} && main::verbose(sprintf('[%s] %s', $self->{name}, $string));
}

##############################################################

package wde::main;
use warnings;
use strict;
use base qw(wde::generic);
use POE;

sub new {
	my ($class, $args) = @_;
    $args->{name} //= __PACKAGE__;
    my $self = $class->SUPER::new($args);

    POE::Session->create(
        object_states => [
            $self   => {
                _start      		=> 'ev_start',
				_default			=> 'ev_default',
				_child				=> 'ev_child',
				ev_got_input		=> 'ev_got_input',
				ev_got_stats		=> 'ev_got_stats',
            }
        ],
    );

}

sub ev_start {
    my ($self, $kernel, $heap, $parameter) = @_[OBJECT, KERNEL, HEAP, ARG0];
    $self->debug('[ev_start]');
	$kernel->alias_set($self->{name});

	##############################
	# serial
	if ($self->{serial}{enable}) {
		if (exists $self->{serial_session}) {
			$self->debug('[ev_start] deleting serial session');
		}
		$self->{serial}{debug}    //= $self->{debug};
		$self->{serial}{verbose}  //= $self->{verbose};
		$self->{serial}{this} 		= wde::serial->new($self->{serial});
	}

	##############################
	# file
	if ($self->{file}{enable}) {
		if (exists $self->{file_session}) {
			$self->debug('[ev_start] deleting file session');
		}
		$self->{file}{debug}   //= $self->{debug};
		$self->{file}{verbose} //= $self->{verbose};
		$self->{file}{this}      = wde::file->new($self->{file});
	}

	##############################
	# mqtt
	if ($self->{mqtt}{enable}) {
		if (exists $self->{mqtt_session}) {
			$self->debug('[ev_start] deleting mqtt session');
		}
		$self->{mqtt}{debug} //= $self->{debug};
		$self->{mqtt}{verbose} //= $self->{verbose};
		$self->{mqtt}{this} = wde::mqtt->new($self->{mqtt});
	}

	##############################
	# stats
	if ($self->{stats}{enable}) {
		if (exists $self->{stats_session}) {
			$self->debug('[ev_start] deleting stats session');
		}
		$self->{stats}{debug} //= $self->{debug};
		$self->{stats}{verbose} //= $self->{verbose};
		$self->{stats}{this} = wde::stats->new($self->{stats});
	}
}

sub ev_got_input {
    my ($self, $kernel, $heap, $module, $line) = @_[OBJECT, KERNEL, HEAP, ARG0, ARG1];
	my $data = $self->parse_wde($line);
    $self->debug(sprintf('[ev_got_input][module:%s] sensors:(%s)', $module, (join ' ', map {"$_:(temp:$data->{$_}{temp},hum:$data->{$_}{hum})"} keys %$data)));
	# XXX template topic name
	foreach my $sensor (keys %$data) {
    	$self->debug(sprintf('[ev_got_input][module:%s] mqtt broker:%s topic:%s', $module, $self->{mqtt}{broker}, $self->{mqtt}{topic}));
		$kernel->call($self->{mqtt}{name}, 'ev_do_output', $data->{$sensor});
	}
}

sub ev_got_stats {
    my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
    # $self->verbose(sprintf('[ev_got_stats] every:%s', $self->{stats}{every}));
	my $stats = {};

	foreach my $module (qw(serial file mqtt stats)) {
		if ($self->{$module}{enable}) {
			$stats->{modules}{$module} = sprintf('input:%s,error:%s', $self->{$module}{this}->{last_input_at} // '', $self->{$module}{this}->{last_error_at} // '');
		}
	}
    $self->debug(sprintf('[ev_got_stats] every:%s modules:(%s)', $self->{stats}{every}, (join ',', map {"$_:$stats->{modules}{$_}"} keys %{$stats->{modules}})));
		
}

sub parse_wde {
	my ($self, $line) = @_;
	# $1;1;;8,8;;;;;;;;79;;;;;;;;;;;;;0
	my @fields = split /;/, $line;
	my @temp = @fields[ 3 .. 10];
	my @hum  = @fields[11 .. 19];
	my $data = {};
	for my $sensor (0 .. 7) {
		if (length $temp[$sensor] and length $hum[$sensor]) {
			$temp[$sensor] =~ s/,/./g;
			$hum[$sensor]  =~ s/,/./g;
			$data->{$sensor} = {
				temp	=> $temp[$sensor],
				hum		=> $hum[$sensor]
			};
    		$self->verbose(sprintf('[parse_wde] sensor:%s temp:%s hum:%s', $sensor, $data->{$sensor}{temp}, $data->{$sensor}{hum}));
		}
	}
	return $data;
}

1;

##############################################################

package wde::serial;
use warnings;
use strict;
use base qw(wde::generic);
use POE;
use Device::SerialPort;
use POE::Filter::Line;
use Symbol;

sub new {
	my ($class, $args) = @_;
    $args->{name} //= __PACKAGE__;
    my $self = $class->SUPER::new($args);

    POE::Session->create(
        object_states => [
            $self   => {
                _start      		=> 'ev_start',
				_default			=> 'ev_default',
				_child				=> 'ev_child',
				ev_got_input		=> 'ev_got_input',
				ev_got_error 		=> 'ev_got_error',
                ev_start_serial     => 'ev_start_serial',
            }
        ],
    );
	return $self;
}


sub ev_start {
    my ($self, $kernel, $heap, $parameter) = @_[OBJECT, KERNEL, HEAP, ARG0];
    $self->debug(sprintf('[ev_start] port:%s', $self->{port}));
	$kernel->alias_set($self->{name});

	$self->{last_input_at} = undef;
	$self->{last_error_at} = undef;

    $kernel->yield('ev_start_serial');
}

sub start_serial {
    my ($self) = @_;
    $self->verbose(sprintf('[start_serial] %s', (join ' ', map { "$_:".($self->{$_} // '') } qw(port baudrate datatype databits parity stopbits handshake))));
	# Open a serial port, and tie it to a file handle for POE.
	my $handle = Symbol::gensym();
	$self->{port_handle} = tie(*$handle, "Device::SerialPort", $self->{port});
	die "can't open port:$self->{port} $!" unless $self->{port_handle};
	$self->{port_handle}->datatype('raw');
	# minicom -D /dev/ttyUSB0 -b 115200
	# socat /dev/ttyUSB0,B9600 STDOUT
	$self->{port_handle}->baudrate($self->{baudrate});
	defined $self->{databits} &&  $self->{port_handle}->databits($self->{databits});
	defined $self->{parity}   &&  $self->{port_handle}->parity($self->{parity});
	defined $self->{stopbits} &&  $self->{port_handle}->stopbits($self->{stopbits});
	defined $self->{handshake} && $self->{port_handle}->handshake($self->{handshake});
	$self->{port_handle}->write_settings();

	# Start interacting with the GPS.
	$self->{port_wheel} = POE::Wheel::ReadWrite->new(
		Handle => $handle,
		Filter => POE::Filter::Line->new(
			InputLiteral  => "\x0D\x0A",    # Received line endings.
			OutputLiteral => "\x0D",        # Sent line endings.
		),
		InputEvent => "ev_got_input",
		ErrorEvent => "ev_got_error",
	);
}

sub ev_start_serial {
    my ($self, $kernel) = @_[OBJECT, KERNEL];
    eval {
        $self->start_serial();
    }; if ($@) {
        my $e = $@;  chomp $e;
        $self->debug(sprintf('error starting serial port:%s (%s), retrying in:%s', $self->{port}, $e, $self->{restart_on_error_delay}));
        $self->stop_serial();
        $kernel->delay('ev_start_serial', $self->{restart_on_error_delay}); 
    }
}

sub stop_serial {
    my ($self) = @_;
    $self->verbose(sprintf('[stop_serial] port:%s', $self->{port}));
	delete $self->{port_wheel};
	delete $self->{port_handle};
}

sub ev_got_input {
    my ($self, $kernel, $heap, $line) = @_[OBJECT, KERNEL, HEAP, ARG0];
	chomp $line;
    $self->verbose(sprintf('[ev_got_input] port:%s line:%s callback:(%s/%s)', $self->{port}, $line, $self->{input_callback}{session}, $self->{input_callback}{event}));
	$self->{last_input_at} = time;
	$kernel->call($self->{input_callback}{session}, $self->{input_callback}{event}, $self->{name}, $line);
}

sub ev_got_error {
    my ($self, $kernel, $heap, $operation, $errnum, $errstr, $id) = @_[OBJECT, KERNEL, HEAP, ARG0 .. ARG3];
	$self->{last_error_at} = time;
    $self->debug(sprintf('[ev_got_error] port:%s operation:%s errnum:%s errstr:%s id:%s trying to restart in:%s', $self->{port}, $operation, $errnum, $errstr, $id, $self->{restart_on_error_delay}));

    $self->stop_serial();
    $kernel->delay('ev_start_serial', $self->{restart_on_error_delay}); 
}


1;
##############################################################

package wde::file;
use warnings;
use strict;
use base qw(wde::generic);
use POE;
use POE::Wheel::ReadWrite;
use POE::Driver::SysRW;
use POE::Filter::Line;

sub new {
	my ($class, $args) = @_;
    $args->{name} //= __PACKAGE__;
    my $self = $class->SUPER::new($args);

    POE::Session->create(
        object_states => [
            $self   => {
                _start      	=> 'ev_start',
				_default		=> 'ev_default',
				_child			=> 'ev_child',
				ev_got_line		=> 'ev_got_line',
				ev_got_error	=> 'ev_got_error',
            }
        ],
    );
	return $self;
}


sub ev_start {
    my ($self, $kernel, $heap, $parameter) = @_[OBJECT, KERNEL, HEAP, ARG0];
	$kernel->alias_set($self->{name});
    $self->debug(sprintf('[ev_start] reading file:%s', $self->{path}));
	$self->{last_input_at} = undef;
	$self->{last_error_at} = undef;
	
	my $fh;
	eval {
		if ($self->{path} eq '-') {
			$fh = *STDIN;
		} else {
			$fh = IO::File->new("< ".$self->{path});
		}
	}; if ($@) {
		die ($@);
	}
	unless (defined $fh) {
		die "can't read file:$self->{path}";
	}

	$self->{file_wheel} = POE::Wheel::ReadWrite->new(
		Handle 			=> $fh,
		# OutputHandle => $outfile_fh,
		Driver 			=> POE::Driver::SysRW->new(),
		Filter 			=> POE::Filter::Line->new(),
		InputEvent 		=> 'ev_got_line',
		ErrorEvent 		=> 'ev_got_error'
	);

}

sub ev_got_line {
    my ($self, $kernel, $heap, $line) = @_[OBJECT, KERNEL, HEAP, ARG0];
	$self->{last_input_at} = time;
	chomp $line;
    $self->verbose(sprintf('[ev_got_line] file:%s line:%s callback:(%s/%s)', $self->{path}, $line, $self->{input_callback}{session}, $self->{input_callback}{event}));
	$kernel->call($self->{input_callback}{session}, $self->{input_callback}{event}, $self->{name}, $line);
}

sub ev_got_error {
    my ($self, $kernel, $heap, $operation, $errnum, $errstr, $id) = @_[OBJECT, KERNEL, HEAP, ARG0 .. ARG3];
	$self->{last_error_at} = time;
    $self->debug(sprintf('[ev_got_error] file:%s operation:%s errnum:%s errstr:%s id:%s', $self->{path}, $operation, $errnum, $errstr, $id));
	delete $self->{file_wheel};
}

1;
##############################################################

package wde::stats;
use warnings;
use strict;
use base qw(wde::generic);
use POE;

sub new {
	my ($class, $args) = @_;
    $args->{name} //= __PACKAGE__;
    my $self = $class->SUPER::new($args);

    POE::Session->create(
        object_states => [
            $self   => {
                _start      	=> 'ev_start',
				_default		=> 'ev_default',
				_child			=> 'ev_child',
				ev_got_timer	=> 'ev_got_timer',
            }
        ],
    );
	return $self;
}


sub ev_start {
    my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
	$kernel->alias_set($self->{name});
	$self->{last_input_at} = undef;
	$self->{last_error_at} = undef;
    $self->debug(sprintf('[ev_start] every:%s', $self->{every}));
	# $kernel->delay('ev_got_timer', $self->{every});
	$kernel->yield('ev_got_timer');
}

sub ev_got_timer {
    my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
	$self->{last_input_at} = time;
    # $self->verbose(sprintf('[ev_got_timer] every:%s', $self->{every}));
	$kernel->call($self->{every_callback}{session}, $self->{every_callback}{event}, $self->{name});
	$kernel->delay('ev_got_timer', $self->{every});
}

1;

##############################################################

package wde::mqtt;
use warnings;
use strict;
use base qw(wde::generic);
use POE;
use Net::MQTT::Simple;
use JSON;

sub new {
	my ($class, $args) = @_;
    $args->{name} //= __PACKAGE__;
    my $self = $class->SUPER::new($args);
	$self->{json} = JSON->new();

    POE::Session->create(
        object_states => [
            $self   => {
                _start      	=> 'ev_start',
				_default		=> 'ev_default',
				_child			=> 'ev_child',
				ev_do_output	=> 'ev_do_output',
            }
        ],
    );
 
	return $self;
}

sub ev_start {
    my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
	$kernel->alias_set($self->{name});
	$self->{last_output_at} = undef;
	$self->{last_error_at} = undef;
	$self->{mqtt} = Net::MQTT::Simple->new($self->{broker});
    $self->debug(sprintf('[ev_start] broker:%s', $self->{broker}));
}

sub ev_do_output {
    my ($self, $kernel, $heap, $output) = @_[OBJECT, KERNEL, HEAP, ARG0];
	$self->{last_output_at} = time;
	my $j = $self->j($output);
	if ($self->{retain}) {
		$self->{mqtt}->retain($self->{topic}, $j);
	} else {
		$self->{mqtt}->publish($self->{topic}, $j);
	}
    $self->verbose(sprintf('[ev_do_output] broker:%s topic:%s output:(%s)', $self->{broker}, $self->{topic}, $j));
}

sub j {
	my ($self, $data) = @_;
	return $self->{json}->encode($data);
}
1;
