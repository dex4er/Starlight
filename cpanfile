requires 'perl', '5.008001';

requires 'Plack', '0.9920';

suggests 'IO::Socket::IP';
suggests 'IO::Socket::SSL';
suggests 'Net::SSLeay', '1.49';

feature cygwin => sub {
    recommends 'Win32::Process';
};

on build => sub {
    requires 'Module::Build';
};

on test => sub {
    requires 'HTTP::Tiny';
    requires 'Test::More', '0.88';
    requires 'Test::TCP',  '0.15';
};

feature examples => sub {
    recommends 'Mojolicious';
};

on develop => sub {
    requires 'Devel::Cover';
    requires 'Devel::NYTProf';
    requires 'File::Slurp';
    requires 'Module::Build';
    requires 'Module::Build::Version';
    requires 'Module::Signature';
    requires 'Perl::Critic';
    requires 'Perl::Critic::Community';
    requires 'Perl::Tidy';
    requires 'Pod::Markdown';
    requires 'Pod::Readme';
    requires 'Readonly';
    requires 'Software::License';
    requires 'Test::CheckChanges';
    requires 'Test::CPAN::Changes';
    requires 'Test::CPAN::Meta';
    requires 'Test::DistManifest';
    requires 'Test::Distribution';
    requires 'Test::EOL';
    requires 'Test::Kwalitee';
    requires 'Test::MinimumVersion';
    requires 'Test::More';
    requires 'Test::NoTabs';
    requires 'Test::Perl::Critic';
    requires 'Test::Pod';
    requires 'Test::Pod::Coverage';
    requires 'Test::PPPort';
    requires 'Test::Signature';
    requires 'Test::Spelling';
};