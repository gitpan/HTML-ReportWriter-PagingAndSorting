use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'HTML::ReportWriter::PagingAndSorting',
    'VERSION_FROM'	=> 'PagingAndSorting.pm',
    'PREREQ_PM'		=> {
            'CGI' => 0,
            'List::MoreUtils' => 0,
            'POSIX' => 0,
    },
    'ABSTRACT_FROM'     => 'PagingAndSorting.pm',
    'AUTHOR'            => 'Shane Allen <opiate@gmail.com>',
);
