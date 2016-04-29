# script to apply Aspect J code in com.teamcenter.rac.aspects plugin to the
# eclipse framework in a unit shell;
# prerequisites:
# - make sure that 7z is included in your PATH
# - export com.teamcenter.rac.aspects plugin from ECLIPSE into ./plugins
# Sep-04-2015
use strict;

use File::Path qw(rmtree);
use File::Copy qw(copy);
use File::Copy::Recursive qw(rcopy);

use Cwd;

my $verbose = ($#ARGV >= 0 && $ARGV[0] eq "-v") ? 1 : 0;

my $JAVA_HOME = $ENV{JAVA_HOME};
my $ASPECTJ_HOME = $ENV{TC_TOOLBOX} . "/Aspectj/1.7.2";

my $aspectPlugin = "com.teamcenter.rac.aspects";

my $sourceDir = "./plugins";

my $pluginsDir = "$ENV{ROOT}/$ENV{PLAT}/eclipse/rcp/plugins";

my @jarsToPatch = (
    {
        jar => "org.eclipse.core.expressions_3.4.400.v20120523-2004.jar",
        dependencies => [
            "org.eclipse.core.commands_3.6.1.v20120521-2332.jar",
            "org.eclipse.core.databinding.observable_1.4.1.v20120521-2332.jar",
            "org.eclipse.core.databinding.property_1.4.100.v20120523-1956.jar",
            "org.eclipse.core.jobs_3.5.200.v20120521-2346.jar",
            "org.eclipse.core.runtime_3.8.0.v20120521-2346.jar",
            "org.eclipse.equinox.common_3.6.100.v20120522-1841.jar",
            "org.eclipse.equinox.preferences_3.5.0.v20120522-1841.jar",
            "org.eclipse.equinox.registry_3.5.200.v20120522-1841.jar",
            "org.eclipse.jface_3.8.0.v20120521-2332.jar",
            "org.eclipse.osgi_3.8.0.v20120529-1548.jar",
            "org.eclipse.swt.*_3.8.0.v3833.jar",
            "org.eclipse.ui.workbench_3.8.0.v20120521-2332.jar",
        ]
    },
    {
        jar => "org.eclipse.ui.workbench_3.8.0.v20120521-2332.jar",
        dependencies => [
            "org.eclipse.core.commands_3.6.1.v20120521-2332.jar",
            "org.eclipse.core.databinding.property_1.4.100.v20120523-1956.jar",
            "org.eclipse.core.expressions_3.4.400.v20120523-2004.jar",
            "org.eclipse.core.jobs_3.5.200.v20120521-2346.jar",
            "org.eclipse.core.runtime_3.8.0.v20120521-2346.jar",
            "org.eclipse.equinox.common_3.6.100.v20120522-1841.jar",
            "org.eclipse.equinox.preferences_3.5.0.v20120522-1841.jar",
            "org.eclipse.equinox.registry_3.5.200.v20120522-1841.jar",
            "org.eclipse.jface_3.8.0.v20120521-2332.jar",
            "org.eclipse.osgi_3.8.0.v20120529-1548.jar",
            "org.eclipse.swt.*_3.8.0.v3833.jar",
        ]
    }
);

my $isWindows = ($ =~ /^mswin32$/i);

my @tmpDirs;

END {
    print "\n- Cleanup:\n";

    foreach (@tmpDirs)
    {
        print "  Removing temporary directory \"$_\"\n";
        rmtree($_, $verbose);
    }
}

my $cnt = 1;

opendir(DIR, $sourceDir) or die "Failed to read directory \"$sourceDir\": $!";

my $plugin;
my $pluginMTime;
while ($_ = readdir(DIR))
{
    my $file = $sourceDir . "/" . $_;
    if (-f  $file && substr($_, 0, length($aspectPlugin)) eq $aspectPlugin)
    {
        if (not $pluginMTime or ($pluginMTime < (stat($file))[9]))
        {
            $pluginMTime < (stat($file))[9];
            $plugin = $file;
        }
    }
}

closedir(DIR);

die "Didn't find any suitable $aspectPlugin plugin in $sourceDir" unless $plugin;

my $failure;

foreach (@jarsToPatch)
{
    my $jarToPatch = $pluginsDir . "/" . $_->{jar};
    my @dependencies = @{$_->{dependencies}};

    my $jarBaseName = $jarToPatch;
    $jarBaseName =~ s:^.*[/\\]::;

    if (!-f "$jarToPatch.org")
    {
        print "- Backing up $jarToPatch to $jarBaseName.org\n";
        rename($jarToPatch, "$jarToPatch.org") or die "*** Failed to backup $jarToPatch $!";
    }

    $failure = 1;
    END {
          if ($failure) {
            print STDERR "Restoring \"$jarBaseName\" from \"$jarToPatch.org\"\n" if $verbose;
            copy("$jarToPatch.org", $jarToPatch);
        } }

    my $tmpDir = (defined $ENV{TEMP} ? $ENV{TEMP} : "/tmp") . "/patchrcp.$$.$cnt";
    $cnt++;

    mkdir $tmpDir or die "Failed to create temporary directory \"$tmpDir\": $!";
    push(@tmpDirs, $tmpDir);

    print "- Applying $plugin to $jarToPatch\n";

    my $CLASSPATH = "$ASPECTJ_HOME/aspectjrt.jar;$ASPECTJ_HOME/aspectjtools.jar;$JAVA_HOME/lib/tools.jar;" . 
        join(";", map { $pluginsDir."/".$_ } @dependencies) . ";" . $ENV{CLASSPATH};

    my $dependencies = join(';', map {
        my @plugins = glob("$pluginsDir/$_");
        print "WARNING: The plugin \"$_\" does not exist in the plugins directory \"$pluginsDir\"\n" unless scalar(@plugins);
        $_ = join(';', @plugins);
    } @dependencies);

    $CLASSPATH .= $dependencies;

    $CLASSPATH =~ s/;/:/g unless $isWindows;

    my $cmd = "\"$JAVA_HOME/bin/java\" -classpath \"$CLASSPATH\" -Xmx64M org.aspectj.tools.ajc.Main " .
        "-1.6 -inpath \"$jarToPatch.org\" -outjar \"$jarToPatch\" ";

    $cmd .= "-aspectpath $plugin";

    $cmd =~ s:/:\\:g if $isWindows;

    print "- Executing cmd $cmd\n" if $verbose;

    my $exitCode = system($cmd);

    if ($exitCode != 0)
    {
        print STDERR "*** The Aspect J compiler failed with exit code $exitCode\n";
        exit($exitCode);
    }
    print "- Aspect J compilation succeeded, patching manifest file\n";

    my $pwd = getcwd();
    chdir $tmpDir or "*** Failed to cd to temporary directory $tmpDir: $!";

    END { chdir $pwd }

    $cmd = "7z x \"$jarToPatch\" META-INF/MANIFEST.MF";
    print "- Executing cmd \"$cmd\"\n" if $verbose;

    $exitCode = system($cmd);
    
    die "*** Failed to extract MANIFEST file: 7z exited with error code $exitCode" if $exitCode;

    rename("META-INF/MANIFEST.MF", "META-INF/MANIFEST.MF.org") or die "*** Failed to rename extracted manifest file: $!";

    open(IN, "META-INF/MANIFEST.MF.org") or die "Failed to open extracted manifest file: $!";
    open(OUT, ">META-INF/MANIFEST.MF" ) or die "Failed to write to temporary manifest file: $!";

    my $patched = 0;
    while (<IN>)
    {
        s/[\r\n]+$/\n/;

        if (/Import-Package:/)
        {
            my $s = $_;
            while (<IN>)
            {
                s/[\r\n]+$/\n/;
                last if (/^\S/);
                $s .= $_;
            }

            chomp($s);
            $s .= ",\n" . "  org.aspectj.lang, $aspectPlugin\n";

            print OUT $s;
            $patched = 1;
        }

        print OUT;
    }

    if (!$patched)
    {
        print OUT "Import-Package: org.aspectj.lang, $aspectPlugin\n";
    }

    close(IN);
    close(OUT);

    $cmd = "7z u \"$jarToPatch\" META-INF/MANIFEST.MF";

    print "- Executing cmd \"$cmd\"\n" if $verbose;
    $exitCode = system($cmd);

    die "*** Failed to update MANIFEST file: 7z exited with error code $exitCode" if $exitCode;

    chdir($pwd);

    $failure = 0;
}

print "- Copying Aspect plugin $aspectPlugin to $pluginsDir\n";

opendir(DIR, $pluginsDir) or die "Failed to open plugins directory \"$pluginsDir\": $!";

while ($_ = readdir(DIR))
{
    if (/${aspectPlugin}_.*\.jar/)
    {
        my $file = $pluginsDir . "/" . $_;
        print "  Removing $file\n" if $verbose;
        unlink($file) or die "Failed to remove \"$file\": $!";
    }
}

closedir(DIR);

copy($plugin, $pluginsDir) or die "*** Failed to copy the aspect plugin \"$plugin\" to \"$pluginsDir\": $!";

if (scalar(glob("$pluginsDir/org.aspectj.runtime_*")) == 0)
{
    print "- Copying org.aspectj.runtime plugin to $pluginsDir\n";

    my @plugins = glob("$sourceDir/org.aspectj.runtime_*");

    die "*** No org.aspectj.runtime plugin found in $sourceDir" unless $#plugins >= 0;
    die "*** Multiple org.aspectj.runtime plugins found in $sourceDir: please delete any suplerfluous plugins" if $#plugins > 0;

    my $basename = $plugins[0];
    $basename =~ s:.*[/\\]::;

    rcopy($plugins[0], "$pluginsDir/$basename") or die "Failed to copy \"" . $plugins[0] . " to \"$pluginsDir\": $!";
}
