package MailForm::Misc;

use strict;
use MT::Util qw( remove_html );

# upgrade function from 2.0 (schema version 1.0) to 2.1 (schema version 1.01)
sub add_author_id_field {
    my $plugin = MT->component('mailform');

    # load root user
    my $iter = MT::Author->load_iter({ type => MT::Author::AUTHOR() });
    my $author;
    while ($author = $iter->()) {
        last if (!$author->created_by);
    }
    die $plugin->translate('Can\'t find root user') if (!$author);

    # set user to mail form settings
    $iter = MailForm::Setting->load_iter;
    my $setting;
    while ($setting = $iter->()) {
        $setting->author_id($author->id);
        $setting->save or die $plugin->translate('Can\'t set user to mail form setting');
    }
}

sub title_html {
    my ( $prop, $obj ) = @_;
    my $class = $obj->class;
    my $title = remove_html($obj->title);
    my $edit_url = MT->app->uri(
        mode => 'fjmf_do_setting',
        args => {
            blog_id => $obj->blog_id,
            id => $obj->id,
        },
    );
    my $out = <<HERE;
<span class="view-link"><a href="$edit_url">$title</a></span>
HERE
    return $out;
}

sub init_app {
    my $app = shift;
    my $plugin = MT->component('mailform');
    bless $plugin, 'MT::Plugin::MailForm';
}

package MT::Plugin::MailForm;

use MT::Plugin;
use MT::Blog;
use base qw( MT::Plugin );

sub load_config {
    my ($plugin, $param, $scope) = @_;

    $plugin->SUPER::load_config($param, $scope);
    return if ($scope eq 'system');

    my $app = MT->instance;
    my $blog = $app->blog;
    $param->{fjmf_blog_id} = $blog->id;
}

1;
