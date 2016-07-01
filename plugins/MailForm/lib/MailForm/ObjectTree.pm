package MailForm::ObjectTree;

use strict;
use warnings;

use constant PER_REQUEST => 50;

sub load_mail_forms {
    my $app = shift;
    my $plugin = MT->component('ObjectTree');

    my $blog_id = $app->param('blog_id');
    my $blog = MT->model('blog')->load($blog_id);
    return $app->json_error('Illegal blog_id') if (!$blog);
    my $class = $app->param('class');
    return $app->json_error('Illegal class') if ($class ne 'mailform_setting');
    my $class_label = MT->model($class)->class_label;
    my $offset = $app->param('offset');
    my %result = ();

    # create filter
    my $filter = MT->model('filter')->new;
    $filter->set_values({
        object_ds => $class,
        items     => [],
        author_id => $app->user->id,
        blog_id   => $blog_id,
    });

    my $scope = $blog->is_blog ? 'blog' : 'website';
    my %terms = ( blog_id => $blog_id );
    my %load_options = (
        terms      => \%terms,
        args       => {},
        sort_by    => 'title',
        sort_order => 'ascend',
        limit      => PER_REQUEST,
        offset     => $offset,
        scope      => $scope,
        blog       => $blog,
        blog_id    => $blog_id,
        blog_ids   => [ $blog_id ],
    );

    my %count_options = (
        terms    => \%terms,
        args     => {},
        scope    => $scope,
        blog     => $blog,
        blog_id  => $blog_id,
        blog_ids => [ $blog_id ],
    );

    my @cols = ( 'id', 'blog_id', 'title' );

    # count assets
    MT->run_callbacks(
        'cms_pre_load_filtered_list.' . $class,
        $app, $filter, \%count_options, \@cols
    );
    my $count_result = $filter->count_objects(%count_options);

    # load assets
    my ($total_count, $editable_count) = @$count_result;
    $load_options{total} = $total_count;
    MT->run_callbacks(
        'cms_pre_load_filtered_list.' . $class,
        $app, $filter, \%load_options, \@cols
    );
    my $settings = $filter->load_objects(%load_options);
    $app->run_callbacks('object_tree_bulk_filter.mailform_setting', $settings);

    # out result
    my $resources = MT->registry('tree_resources');
    my @result = map {
        my $setting = $_;
        my $setting_res = $resources->{$class}->($setting);
        $setting_res;
    } @$settings;
    $result{items} = \@result;
    if (!$offset) {
        $result{count} = scalar @$settings;
    }
    $result{offset} = $offset;
    $result{per_request} = PER_REQUEST;
    $result{blog} = { id => $blog->id, name => $blog->name };
    return $app->json_result(\%result);
}

sub resources {
    return {
        mailform_setting => sub {
            my $setting = shift;
            return {
                class => 'mailform_setting',
                id => $setting->id,
                blog_id => $setting->blog_id,
                label => $setting->title,
            };
        },
    };
}

sub edit_tree {
    my ($cb, $app, $param, $tmpl) = @_;
    my $plugin = MT->component('mailform');

    # search <mt:include name="include/header.tmpl">
    my $elements = $tmpl->getElementsByTagName('include');
    my $head_node;
    for my $element (@$elements) {
        if (
            $element->attributes->{name} eq 'include/header.tmpl'
            ||
            $element->attributes->{name} eq 'dialog/header.tmpl'
        ) {
            $head_node = $element;
            last;
        }
    }

    if ($head_node) {
        my $node = $tmpl->createElement('setvarblock', { name => 'js_include', append => 1 });
        my $innerHTML = <<HERE;
<script type="text/javascript" src="<mt:var name="static_uri">plugins/MailForm/js/object_tree.js"></script>
HERE
        $node->innerHTML($innerHTML);
        $tmpl->insertBefore($node, $head_node);
    }
}

1;
