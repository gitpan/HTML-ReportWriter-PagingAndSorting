package HTML::ReportWriter::PagingAndSorting;

use strict;
use POSIX;
use CGI;
use List::MoreUtils qw(none firstidx);

our $VERSION = '1.0.1';

=head1 NAME

HTML::ReportWriter::PagingAndSorting - Contains logic for paging/sorting function of ReportWriter

=head1 SYNOPSIS

Example script:

 #!/usr/bin/perl -w

 use strict;
 use HTML::ReportWriter::PagingAndSorting;
 use CGI;
 use Template;
 use DBI;

 my $template = Template->new( { INCLUDE_PATH => '/templates' } );
 my $co = new CGI;
 my $paging = HTML::ReportWriter::PagingAndSorting->new({
             CGI_OBJECT => $co,
             ASC_IMAGE => 'http://www.example.com/u.gif',
             DESC_IMAGE => 'http://www.example.com/d.gif',
             DEFAULT_SORT => 'date',
             sortable_columns => [
                 {
                     get => 'name',
                     sql => 'people.name',
                     display => 'Full Name',
                     sortable => 0,
                 },
                 {
                     get => 'age',
                     sql => 'people.age',
                     display => 'Age (in years)',
                     sortable => 1,
                 },
             ],
 });

 my $dbh = DBI->connect('DBI:mysql:foo', 'bar', 'baz');

 my $sql = "SELECT SQL_CALC_FOUND_ROWS id, name, age FROM people";

 my $sort = $paging->get_mysql_sort();
 my $limit = $paging->get_mysql_limit();

 my $sth = $dbh->prepare("$sql $sort $limit");
 $sth->execute();
 my ($count) = $dbh->selectrow_array('SELECT FOUND_ROWS() AS num');

 $paging->num_results($count);

 while(my $href = $sth->fetchrow_hashref)
 {
     push @{$vars{'results'}}, $href;
 }
 $vars{'sorting'} = $paging->get_sortable_table_header();
 $vars{'paging'} = $paging->get_paging_table();

 print $co->header;
 $template->process('display.html', \%vars);

Example template (display.html in the above example):

 <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
 <html>
 <head>
 <title>Simple Report</title>
 <link rel="STYLESHEET" type="text/css" href="/style.css" xmlns="">
 </head>
 <body>
 [% rowcounter = 1 %]
 <center>
 <table border="0" width="800">
 <tr><td>
 <table id="idtable" border="0" cellspacing="0" cellpadding="4" width="100%">
 [% sorting %]
 [%- FOREACH x = results %]
     [%- IF rowcounter mod 2 %]
         [%- rowclass = "table_odd" %]
     [%- ELSE %]
         [%- rowclass = "table_even" %]
     [%- END %]
 <tr class="[% rowclass %]">
 <td>[% x.name %]</td><td>[% x.age %]</td>
 </tr>
     [%- rowcounter = rowcounter + 1 %]
 [% END %]
 </table>
 </td></tr>
 <tr><td>
 <table border="0" width="100%">
 <tr>
 <td width="75%"></td><td width="25%">[% paging %]</td>
 </tr>
 </table>
 </td></tr>
 </table>
 </center>
 <br /><br />
 </body>
 </html>

The DB is left to the reader's imagination.

=head1 DESCRIPTION

Generates HTML table headers and footers to handle sorting and paging for tabular reports.
Additionally, generates SQL fragments to insert into queries to handle paging and sorting.

=head1 METHODS

=over

=item B<new($options)>

Creates and returns a new paging object. new() accepts a single hashref as an argument, options.
Options may be one or more of the following:

=over

=item CGI_OBJECT:

A previously-created CGI object. Saves the overhead of loading a new one.

=item RESULTS_PER_PAGE:

The number of rows to be displayed per page. default: 25

=item PAGES_IN_LIST:

The number of pages that will appear in the paging array. default: 5
Note: this number must be odd. If it is even, it will be decremented by 1.

=item PAGE_VARIABLE:

The GET parameter that defines which page of the results we are viewing. default: page

=item NUM_RESULTS:

This should not be used when instantiating the object, because it means that in doing so
you have bypassed the get_mysql_limit function, which is against the design of this object.

=item SORT_VARIABLE:

The GET parameter that defines which column is being used for sorting and the direction of the
sort. default: sort

=item SORT_DEFAULT:

Which column should be sorted by when the page is drawn for the first time. default: blank
Note: If you specify a default column but no default direction, the sort defaults to ascending.

=item CURRENT_PAGE:

Which page are we currently viewing? Should never need to be overridden.
default: $cgi->param(PAGE_VARIABLE)

=item CURRENT_SORT_COL:

Which column are we currently sorting by? Should never need to be overridden.

=item CURRENT_SORT_DIR:

Which direction are we currently sorting? Should never need to be overridden.

=back

The following options control formatting, and should be self-explanatory. Their defaults
are listed next to the item.

=over

=item FONT_COLOR     black

=item HILIGHT_COLOR  #555555

=item PREV_HTML      &lt;

=item NEXT_HTML      &gt;

=item FIRST_HTML     &laquo;

=item LAST_HTML      &raquo;

=item ASC_IMAGE      /img/standard/asc.gif

=item DESC_IMAGE     /img/standard/desc.gif

=back

Finally, it accepts a list of sortable columns. A column consists of the following properties:

=over

=item get:

The name of the column on the get string. This is used in conjunction with SORT_VARIABLE as in:
C<< http://example.com/cgi-bin/reports/foo.cgi?SORT_VARIABLE=SORTABLE_COLUMNS->[0]->{'get'} >>

=item sql:

The name of the column in sql. Include any necessary table aliases in this definition.
Example: C<< sql => 'tablename.columnname' >>

=item display:

The name of the column in the display. Used by get_sortable_html_table_header

=item sortable:

True/False (1/0). Defines the behaviour of the column. Does it allow sorting?

=back

Each sortable column definition is a hashref, and SORTABLE_COLUMNS itself is an arrayref containing
one or more of these hashrefs. Example:

 SORTABLE_COLUMNS => [
         {
             'get' => 'name',
             'sql' => 'person.name',
             'display' => 'Name',
             'sortable' => 0,
         },
         {
             'get' => 'age',
             'sql' => 'person.age',
             'display' => 'Age (in years)',
             'sortable' => 1,
         },
 ]

=cut

sub new
{
    my ($pkg, $args) = @_;

    if(!defined($args->{'CGI_OBJECT'}) || !UNIVERSAL::isa($args->{'CGI_OBJECT'}, "CGI"))
    {
        $args->{'CGI_OBJECT'} = new CGI;
        warn "Creating new CGI object";
    }

    # paging setup
    defined $args->{'RESULTS_PER_PAGE'} or $args->{'RESULTS_PER_PAGE'} = 25;
    defined $args->{'PAGES_IN_LIST'} or $args->{'PAGES_IN_LIST'} = 5;
    defined $args->{'PAGE_VARIABLE'} or $args->{'PAGE_VARIABLE'} = 'page';
    defined $args->{'NUM_RESULTS'} or $args->{'NUM_RESULTS'} = 0;

    # sorting setup
    defined $args->{'SORT_VARIABLE'} or $args->{'SORT_VARIABLE'} = 'sort';
    defined $args->{'SORT_DEFAULT'} or $args->{'SORT_DEFAULT'} = '';

    # current page handling
    my $page = $args->{'CGI_OBJECT'}->param($args->{'PAGE_VARIABLE'}) || 1;
    defined $args->{'CURRENT_PAGE'} or $args->{'CURRENT_PAGE'} = $page;

    # current sort handling
    my $sort = $args->{'CGI_OBJECT'}->param($args->{'SORT_VARIABLE'}) || $args->{'DEFAULT_SORT'};
    my ($sort_col, $sort_dir);
    if($sort)
    {
        ($sort_col, $sort_dir) = split /,/, $sort;
    }

    if(!$sort_dir && $sort_col)
    {
        # defaults to ascending order
        $sort_dir = 'ASC';
    }
    defined $args->{'CURRENT_SORT_COL'} or $args->{'CURRENT_SORT_COL'} = $sort_col;
    defined $args->{'CURRENT_SORT_DIR'} or $args->{'CURRENT_SORT_DIR'} = $sort_dir;

    # options to control HTML output - Paging
    defined $args->{'PAGES_IN_LIST'} or $args->{'PAGES_IN_LIST'} = 5;
    defined $args->{'FONT_COLOR'} or $args->{'FONT_COLOR'} = 'black';          
    defined $args->{'HILIGHT_COLOR'} or $args->{'HIGHLIGHT_COLOR'} = '#555555';
    defined $args->{'PREV_HTML'} or $args->{'PREV_HTML'} = '&lt;';
    defined $args->{'NEXT_HTML'} or $args->{'NEXT_HTML'} = '&gt;';
    defined $args->{'FIRST_HTML'} or $args->{'FIRST_HTML'} = '&laquo;';
    defined $args->{'LAST_HTML'} or $args->{'LAST_HTML'} = '&raquo;';

    # options to control HTML output - Sorting
    defined $args->{'ASC_IMAGE'} or $args->{'ASC_IMAGE'} = '/img/standard/asc.gif';
    defined $args->{'DESC_IMAGE'} or $args->{'DESC_IMAGE'} = '/img/standard/desc.gif';

    # round down PAGES_IN_LIST if it isn't odd
    if(!$args->{'PAGES_IN_LIST'} % 2)
    {
        $args->{'PAGES_IN_LIST'} -= 1;
        warn "PAGES_IN_LIST must be odd. See the documentation (if it exists) for the reason why.";
    }

    # don't die here because they may not want to use the sorting, but may have a GET/POST var whose name is the
    # same as $args->{'SORT_VARIABLE'}. We'll die if they call a sort function.
    if(($sort_dir || $sort_col) && !$args->{'sortable_columns'} || ref($args->{'sortable_columns'}) ne 'ARRAY')
    {
        warn "sortable_columns is either not defined or not an arrayref, sorting disabled";
    }

    my $self = bless $args, $pkg;

    return $self;
}

=item B<num_results($int)>

Accepts the number of results that will be generated for the query being used. Sets the number of
rows internally to the number supplied, and returns that number as confirmation of the setting.

=cut

sub num_results
{
    my ($self, $num) = @_;

    return ($self->{'NUM_RESULTS'} = $num);
}

=item B<generate_paging_array()>

Determines what page the viewer is currently on, and generates an array representing which
pages are previous and next, first and last. Returns that array.

=cut

sub generate_paging_array
{
    my $self = shift;

    my $pages_on_either_side = ceil(($self->{'PAGES_IN_LIST'} - 1) / 2);
    my $total_pages = ceil($self->{'NUM_RESULTS'} / $self->{'RESULTS_PER_PAGE'});

    # if somehow we paged past the end of the results, get us back on track
    if($self->{'CURRENT_PAGE'} > $total_pages)
    {
        $self->{'CURRENT_PAGE'} = $total_pages;
    }

    my @pages = ();

    # at the end of the results
    if($self->{'CURRENT_PAGE'} == $total_pages)
    {
        my $min = $self->{'CURRENT_PAGE'} - $self->{'PAGES_IN_LIST'};
        $min = 1 if $min < 1;

        push @pages, $min..$self->{'CURRENT_PAGE'};
    }
    # just right
    elsif(($self->{'CURRENT_PAGE'} - $pages_on_either_side) >= 1 &&
            ($self->{'CURRENT_PAGE'} + $pages_on_either_side) <= $total_pages)
    {
        my $min = $self->{'CURRENT_PAGE'} - $pages_on_either_side;
        my $max = $self->{'CURRENT_PAGE'} + $pages_on_either_side;

        push @pages, $min..$max;
    }
    # too close to the beginning
    elsif($self->{'CURRENT_PAGE'} - $self->{'PAGES_IN_LIST'} < 1)
    {
        my $min = 1;
        if($self->{'PAGES_IN_LIST'} > $total_pages)
        {
            push @pages, $min..$total_pages;
        }
        else
        {
            push @pages, $min..$self->{'PAGES_IN_LIST'};
        }
    }
    # too close to the end
    elsif($self->{'CURRENT_PAGE'} + $self->{'PAGES_IN_LIST'} > $total_pages)
    {
        my $min = $self->{'CURRENT_PAGE'} - ($self->{'PAGES_IN_LIST'} - ($total_pages - $self->{'CURRENT_PAGE'}));
        $min = 1 if $min < 1;

        push @pages, $min..$total_pages;
    }
    else
    {
        die "This code should never execute";
    }

    return (@pages);
}

=item B<get_page_link($page_number)>

Saves the existing sort and page settings, and then uses some CGI module magic to generate
a URL saving all parameters that were passed in except the page number, which is set to the
requested page. Used to generate paging html.

=cut

sub get_page_link
{
    my ($self, $page) = @_;

    # save the old page number and sort (this is necessary since we have a shared CGI object)
    my $oldpage = $self->{'CGI_OBJECT'}->param($self->{'PAGE_VARIABLE'});

    # generate a url with the new page number
    $self->{'CGI_OBJECT'}->param($self->{'PAGE_VARIABLE'}, $page);
    my $url = $self->{'CGI_OBJECT'}->url( -absolute => 1, -query => 1 );

    # restore the old page number
    if($oldpage)
    {
        $self->{'CGI_OBJECT'}->param($self->{'PAGE_VARIABLE'}, $oldpage);
    }
    else
    {
        $self->{'CGI_OBJECT'}->delete($self->{'PAGE_VARIABLE'});
    }

    return $url;
}

=item B<get_paging_table()>

Gets the paging array, generates links for each part of that array, and then generates HTML for
the paging block based on the display settings that were configured during instantiation.

=cut

sub get_paging_table
{
    my ($self) = @_;
    die "You cannot draw paging for a page with no results!" if $self->{'NUM_RESULTS'} == 0;

    my @paging_array = $self->generate_paging_array();

    my $total_pages = ceil($self->{'NUM_RESULTS'} / $self->{'RESULTS_PER_PAGE'});
    my $string = '';

    # paging header
    $string = '<table class="paging-table"><tr>';
    $string = '<td nowrap class="paging-td" style="font-size: 7pt;">Displaying Results '
        . ($self->{'CURRENT_PAGE'} == 1 ? 1 : (($self->{'CURRENT_PAGE'} - 1) * $self->{'RESULTS_PER_PAGE'}))
        . ' to '
        . ($self->{'CURRENT_PAGE'} == $total_pages ? $self->{'NUM_RESULTS'} : ($self->{'CURRENT_PAGE'} * $self->{'RESULTS_PER_PAGE'}))
        . ' of '
        . $self->{'NUM_RESULTS'} . '</td>';

    # process the elements in order
    foreach ('FIRST','PREV',@paging_array,'NEXT','LAST')
    {
        $string .= '<td class="paging-td">';

        if(($_ eq 'FIRST' || $_ eq 'PREV') && $self->{'CURRENT_PAGE'} != 1)
        {
            my $url = $self->get_page_link(($_ eq 'FIRST' ? 1 : $self->{'CURRENT_PAGE'} - 1));
            $string .= qq(<a class="paging-a" href="$url">) . $self->{"${_}_HTML"} . q(</a>);
        }
        elsif(($_ eq 'NEXT' || $_ eq 'LAST') && $self->{'CURRENT_PAGE'} != $total_pages)
        {
            my $url = $self->get_page_link(($_ eq 'LAST' ? $total_pages : $self->{'CURRENT_PAGE'} + 1));
            $string .= qq(<a class="paging-a" href="$url">) . $self->{"${_}_HTML"} . q(</a>);
        }
        elsif($_ eq 'FIRST' || $_ eq 'PREV' || $_ eq 'NEXT' || $_ eq 'LAST')
        {
            $string .= $self->{"${_}_HTML"};
        }
        elsif($_ != $self->{'CURRENT_PAGE'})
        {
            my $url = $self->get_page_link($_);
            $string .= qq(<a class="paging-a" href="$url">$_</a>);
        }
        else
        {
            $string .= $_;
        }

        $string .= '</td>';
    }

    # paging footer
    $string .= '</tr></table>';

    return $self->get_paging_stylesheet() . $string;
}

=item B<get_mysql_limit()>

Generates a MySQL-compliant LIMIT clause to be appended to SQL queries in order to get the
appropriate rows for a paged report. Example above, in the SYNOPSIS.

=cut

sub get_mysql_limit
{
    my $self = shift;

    my $start = ($self->{'CURRENT_PAGE'} - 1) * $self->{'RESULTS_PER_PAGE'};
    my $count = $self->{'RESULTS_PER_PAGE'};

    return "LIMIT $start, $count";
}

=item B<get_paging_stylesheet()>

Returns an inline stylesheet block for the paging html based on the display settings provided during
object instantiation. Currently this is called and prepended to the return value of get_paging_html.

=cut

sub get_paging_stylesheet
{
    my $self = shift;

    my $string = '';
    $string .= '<style type="text/css">';
    $string .= '.paging-table {';
        $string .= 'border: 0px solid black;';
    $string .= '}';
    $string .= '.paging-td {';
        $string .= 'padding: 4px;';
        $string .= 'font-weight: none;';
        $string .= 'color: ' . $self->{'HIGHLIGHT_COLOR'} . ';';
    $string .= '}';
    $string .= '.paging-a {';
        $string .= 'color: ' . $self->{'FONT_COLOR'} . ';';
        $string .= 'font-weight: bold;';
        $string .= 'text-decoration: none;';
    $string .= '}';
    $string .= '</style>';

    return $string;
}

=item B<get_mysql_sort()>

Returns a MySQL-compliant ORDER BY clause based on the current sorting settings, to be appended
to the SQL query used to generate the report that this module is being used for. Example above
in the SYNOPSIS.

=cut

sub get_mysql_sort
{
    my ($self) = @_;

    if(!$self->{'sortable_columns'} || ref($self->{'sortable_columns'}) ne 'ARRAY')
    {
        die "sortable_columns is either not defined or not an arrayref, sorting disabled";
    }

    my $dir = uc($self->{'CURRENT_SORT_DIR'});
    my $sort = $self->{'CURRENT_SORT_COL'};
    my $to_return = '';

    if(none { $_->{'get'} eq $sort } @{$self->{'sortable_columns'}})
    {
        die "requested sort '$sort' is impossible, not defined in sortable_columns";
    }

    if($dir && $sort)
    {
        my $index = firstidx { $_->{'get'} eq $sort } @{$self->{'sortable_columns'}};
        if($self->{'sortable_columns'}->[$index]->{'get'} ne $sort)
        {
            die "This should not happen";
        }
        $sort = $self->{'sortable_columns'}->[$index]->{'sql'};
        $to_return = "ORDER BY $sort $dir";
    }

    return $to_return;
}

=item B<get_sort_link($column)>

Same as get_page_link() above, except allows you to specify the new sort instead of the new page.
When specifying the sort column, specifying the same column that is currently selected results
in the link being generated for the opposite of its current direction. Otherwise, each column
defaults to sort ascending.

Additionally, when changing the sort, page is not preserved, the logic being that you likely
want to start back at the beginning of the report to view the first I<n> records instead of being
stuck in the middle of the record set.

=cut

sub get_sort_link
{
    my ($self, $sort) = @_;

    if(!$self->{'sortable_columns'} || ref($self->{'sortable_columns'}) ne 'ARRAY')
    {
        die "sortable_columns is either not defined or not an arrayref, sorting disabled";
    }

    if(none { $_->{'get'} eq $sort } @{$self->{'sortable_columns'}})
    {
        die "requested sort '$sort' is impossible, not defined in sortable_columns";
    }

    # Either you're switching to a new sort col (default ASC) or you're changing the direction of the current sort
    my $dir = ($sort ne $self->{'CURRENT_SORT_COL'} ? 'ASC' :
            ($self->{'CURRENT_SORT_DIR'} eq 'ASC' ? 'DESC' : 'ASC'));

    # save the old page number and sort (this is necessary since we have a shared CGI object)
    my $oldpage = $self->{'CGI_OBJECT'}->param($self->{'PAGE_VARIABLE'});
    my $oldsort = $self->{'CGI_OBJECT'}->param($self->{'SORT_VARIABLE'});

    # set the new sort option, delete page (reset to page 1 on new sort)
    $self->{'CGI_OBJECT'}->param($self->{'SORT_VARIABLE'}, "$sort,$dir");
    $self->{'CGI_OBJECT'}->delete($self->{'PAGE_VARIABLE'});
    my $url = $self->{'CGI_OBJECT'}->url( -absolute => 1, -query => 1 );

    # restore the old page and sort
    if($oldsort)
    {
        $self->{'CGI_OBJECT'}->param($self->{'SORT_VARIABLE'}, $oldsort);
    }
    else
    {
        $self->{'CGI_OBJECT'}->delete($self->{'SORT_VARIABLE'});
    }

    if($oldpage)
    {
        $self->{'CGI_OBJECT'}->param($self->{'PAGE_VARIABLE'}, $oldpage);
    }

    return $url;
}

=item B<get_sortable_table_header()>

Generates the HTML for the table header, containing the column names and (where applicable) links
to change the sort column/direction.

Since the header defines the columns, the columns need to be the same width as they are for the
data. Therefore, we only draw a table row, not a full table as we do with the paging html. This row
should probably be the first row of the table that contains the result set.

The output relies on stylesheet elements that currently do not have a definition anywhere.
You will need to define these stylesheet elements on your own. This will be fixed in a future
release, which hopefully will come soon.

=cut

sub get_sortable_table_header
{
    my ($self) = @_;
    # since this function calls get_sort_link, I'm not going to do the error checks -- let them fall through

    my $string = '<tr class="sortable-header-tr">';

    foreach my $col (@{$self->{'sortable_columns'}})
    {
        # $col == the name of the SQL column (used by reportwriter) - also used as the 1st part of the sort GET variable
        # $self->{'sortable_columns'}->{$col} = {
        #    display_name => 'Display Name',
        #    sortable => 1|0,
        #};

        my $url = ($col->{'sortable'} ? $self->get_sort_link($col->{'get'}) : '');
        $string .= '<td class="sortable-header-td">' . ($url ? qq(<a class="sortable-header-a" href="$url">) : '')
            . $col->{'display'} . ' ' . ($col->{'get'} ne $self->{'CURRENT_SORT_COL'} ? '' :
                    ($self->{'CURRENT_SORT_DIR'} eq 'ASC' ? qq(<img src="$self->{'ASC_IMAGE'}" border="0" />) :
                     qq(<img src="$self->{'DESC_IMAGE'}" border="0" />))) . ($url ? '</a>' : '') . '</td>';
    }

    $string .= '</tr>';

    return $string;
}

1;

=back

=head1 TODO

=over

=item *
split stylesheet handling out of the object, either rely on static stylesheets to just
exist, or accept link to external stylesheet, or ... ?

=item *
allow for overrideable class names on the table elements

=item *
purely CSS design?

=back

=head1 BUGS

=over

=item The sortable table header currently relies on stylesheet classes which do not exist and are
not defined anywhere in this module.

=back

Please report any additional bugs discovered to the author.

=head1 SEE ALSO

This module relies indirectly on the use of the L<DBI> and the L<Template> modules or equivalent.
It relies directly on the use of L<CGI>, L<POSIX>, and L<List::MoreUtils>.

=head1 AUTHOR

Shane Allen E<lt>opiate@gmail.comE<gt>

=head1 ACKNOWLEDGEMENTS

This module was developed during my employ at HRsmart, Inc. L<http://www.hrsmart.com> and its
public release was graciously approved.

=head1 COPYRIGHT

This module is released under the same license as Perl itself.

=cut
