#
# DoSetting.pm
#
# 2008/01/09 2.00 Renewal
#
# Copyright(c) by H.Fujimoto
#
package MailForm::DoSetting;

use strict;

use MT;
use MT::Plugin;
use MT::Blog;
use MT::Template;
use MT::FileMgr;
use MT::Util qw( encode_html );
use MT::I18N;

#use YAML::Tiny;

use MailForm::Setting;

my @setting_columns = qw(
    title description email_to email_to2 email_cc email_bcc
    email_from email_from_type mail_subject
    form_template_id preview_template_id error_template_id 
    post_template_id common_template_id body_template_id
    auto_reply rmail_from
    reply_subject reply_template_id
    error_check_fields error_specific_check error_check_in_preview
    must_check_fields email_confirm wait_msg error_msg
    author_id language preview_error_template
);
my %check_fields = (
    'auto_reply' => 1,
    'email_confirm' => 1,
    'error_check_in_preview' => 1,
);
my %select_fields = (
    'form_template_id' => 1,
    'preview_template_id' => 1,
    'error_template_id' => 1,
    'post_template_id' => 1,
    'common_template_id' => 1,
    'body_template_id' => 1,
    'reply_template_id' => 1,
    'language' => 1,
    'preview_error_template' => 1,
);

sub do_setting {
    my $app = shift;
    my $plugin = MT->component('mailform');

    my %params;
    my $blog_id = $app->param('blog_id');
    return $app->return_to_dashboard( redirect => 1 ) unless ($blog_id);

    my $blog = MT::Blog->load($blog_id);
    $params{blog_id} = $blog_id;
    $params{saved} = $app->param('saved');

    # check permission
    my $perms = $app->permissions
        or return $app->error($plugin->translate('Load permission error'));
    return $app->error($plugin->translate('You have no permission'))
        unless ($perms->can_administer_blog);

    # load mailform templates
    my $selmsg = $plugin->translate('Select template');
    my $tmpl_data = {};
    my @tmpl_module_map;
    for my $type (qw ( form preview error post common body reply )) {
        $tmpl_data->{$type} = [ { tmpl_id => 0,
                                  tmpl_name => $selmsg } ];
    }
    my $iter = MT::Template->load_iter({ blog_id => [0, $blog_id],
                                         type => 'custom' });
    while (my $tmpl = $iter->()) {
        if ($tmpl->name =~ /^mail_(preview|error|post|common|body|reply):(.*)/) {
            my $type = $1;
            my $name = $2;
            if ($tmpl->blog_id == 0) {
                $name = $plugin->translate('(Global)') . $name;
            }
            push @{$tmpl_data->{$type}}, { tmpl_id => $tmpl->id,
                                           tmpl_blog_id => $tmpl->blog_id,
                                           tmpl_name => $name };
            push @tmpl_module_map, "'" . $tmpl->id . "' : " . $tmpl->blog_id;
        }
    };
    my @mailform_info;
    $iter = MT::Template->load_iter({ blog_id => $blog_id,
                                      type => 'index' });
    while (my $tmpl = $iter->()) {
        if ($tmpl->name =~ /^mail_form:(.*)/) {
            my $name = $1;
            push @{$tmpl_data->{form}}, { tmpl_id => $tmpl->id,
                                          tmpl_name => $name };
            push @tmpl_module_map, "'" . $tmpl->id . "' : " . $tmpl->blog_id;
            my $site_url = $blog->site_url;
            $site_url .= '/' unless $site_url =~ m!/$!;
            my $link = $site_url . $tmpl->outfile;
            push @mailform_info, "'" . $tmpl->id . "' : '" . $link . "'";
        }
    };
    $params{mailform_info} = '    { ' . join(",\n      ", @mailform_info) . ' }';
    $params{tmpl_module_map} = '    { ' . join(",\n      ", @tmpl_module_map) . ' }';
    for my $type (qw ( form preview error post common body reply )) {
        $params{$type . '_tmpl_data'} = $tmpl_data->{$type};
    }

    # load authors
    $params{author_id} = $app->user->id;
    $params{is_rootuser} = !($app->user->created_by);
    if ($params{is_rootuser}) {
        my @author_data;
        $iter = MT::Author->load_iter({ type => MT::Author::AUTHOR() });
        my $author;
        while ($author = $iter->()) {
            if ($author->permissions($blog)->can_administer_blog) {
                push @author_data, { a_id => $author->id, a_name => $author->name };
            }
        }
        $params{author_data} = \@author_data;
    }

    # load setting
    my $id = $app->param('id');
    if ($id) {
        my $setting = MailForm::Setting->load($id)
            or return $app->error($plugin->translate('Load Setting Error'));
        $params{id} = $id;
        for my $column (@setting_columns) {
            $params{$column} = $setting->column($column);
        }
        $params{languages} =
            MT::I18N::languages_list($app, $setting->language);
        $params{preview_error_template} = 'preview'
            unless $params{preview_error_template};
    }
    else {
        $params{mail_subject} = $plugin->translate('Sent mail from mail form.');
        $params{reply_subject} = $plugin->translate('Thank you for emailing me.');
        $params{email_to} = $app->user->email;
        $params{email_from} = $app->user->email;
        $params{rmail_from} = $app->user->email;
        for my $type (qw ( form preview error post common body reply )) {
            if ($tmpl_data->{$type}) {
                $params{$type . '_template_id'} = $tmpl_data->{$type}->[1]->{tmpl_id};
            }
        }
        my $wait_msg1 = $plugin->translate('Now processing mail.<br />please wait for a while.');
        my $wait_msg2 = $plugin->translate('Processing mail');
        $params{wait_msg} = <<HERE;
<p>
${wait_msg1}<br />
<img src="<\$MTStaticWebPath\$>images/indicator.gif" width="66" height="66" alt="${wait_msg2}" />
</p>
HERE
        my $error_msg = $plugin->translate('Error occured while processing mail.<br />Please send mail again.');
        $params{error_msg} = <<HERE;
<p>
$error_msg
</p>
HERE
        $params{languages} =
            MT::I18N::languages_list($app, $app->config('DefaultUserLanguage'));
        $params{preview_error_template} = 'preview';
    }
    # show page
    $params{position_actions_bottom} = 1;
    my $tmpl = $plugin->load_tmpl('edit_mailform_setting.tmpl');
    $tmpl->text($plugin->translate_templatized($tmpl->text));
    $app->build_page($tmpl, \%params);
}

sub list_setting {
    my $app = shift;
    my $plugin = MT->component('mailform');

    my %params;
    my $blog_id = $app->param('blog_id');
    return $app->return_to_dashboard( redirect => 1 ) unless ($blog_id);

    $params{blog_id} = $blog_id;

    # check permission
    my $perms = $app->permissions
        or return $app->error($plugin->translate('Load permission error'));
    return $app->error($plugin->translate('You have no permission'))
        unless ($perms->can_administer_blog);

    # set data
    my @data;
    my %terms;
    $terms{blog_id} = $blog_id;
    if (!$app->user->is_superuser) {
        $terms{author_id} = $app->user->id;
    }
    my @settings = MailForm::Setting->load(\%terms);
    my $odd = 0;
    for my $setting (@settings) {
        my $author = MT::Author->load($setting->author_id);
        push @data, { id => $setting->id,
                      author => $author ? $author->name : '',
                      title => $setting->title,
                      description => $setting->description,
                      odd => $odd };
        $odd = !$odd;
    }
    $params{position_actions_top} = 1;
    $params{limit_none} = 1;
    $params{empty_message} = $plugin->translate('No mail form found.');
    $params{listing_screen} = 1;
    $params{object_loop}         = \@data;
    $params{object_label}        = $plugin->translate('Mail Form');
    $params{object_label_plural} = $plugin->translate('Mail Forms');
    $params{object_type}         = 'mailform_setting';
    $params{mode}  = $app->mode;

    # show page
    my $tmpl = $plugin->load_tmpl('list_mailform_setting.tmpl');
    $tmpl->text($plugin->translate_templatized($tmpl->text));
    $app->build_page($tmpl, \%params);
}

sub save_setting {
    my $app = shift;
    my $plugin = MT->component('mailform');

    $app->validate_magic() or return;

    # check permission
    my $perms = $app->permissions
        or return $app->error($plugin->translate('Load permission error'));
    return $app->error($plugin->translate('You have no permission'))
        unless ($perms->can_administer_blog);

    # load / create object
    my $setting;
    my $id = $app->param('id');
    my $blog_id = $app->param('blog_id');
    if ($id) {
        $setting = MailForm::Setting->load($id)
            or return $app->error($plugin->translate('Load Setting Error'));
    }
    else {
        $setting = MailForm::Setting->new;
        $setting->blog_id($app->param('blog_id'));
        $setting->author_id($app->user->id);
    }
    my $org_setting = $setting->clone;

    # name check
    return $app->error($plugin->translate('Title is not specified'))
        if (!$app->param('title'));

    # duplicate check
    if (!$id || $id && $setting->title ne $app->param('title')) {
        my $count = MailForm::Setting->count({ blog_id => $blog_id,
                                               title => $app->param('title') });
        return $app->error($plugin->translate('Already exists same title'))
            if ($count);
    }

    # store setting
    for my $column (@setting_columns) {
        if ($check_fields{$column}) {
            $setting->column($column, $app->param($column) ? 1 : 0);
        }
        elsif ($select_fields{$column}) {
            $setting->column($column, $app->param($column) ? $app->param($column) : 0);
        }
        elsif ($column eq 'email_from_type') {
            $setting->email_from_type($app->param('email_from_type') ? 1 : 0);
        }
        else {
            $setting->column($column, $app->param($column) ? $app->param($column) : '');
        }
    }

    # pre save callback
    $app->run_callbacks('MailForm.pre_save_setting', $app, $setting, $org_setting);

    # save setting
    $setting->save
        or return $app->error($plugin->translate('Save Setting Error'));

    # post save callback
    $app->run_callbacks('MailForm.post_save_setting', $app, $setting, $org_setting);

    # save log
    my ($msg, $category);
    if (!$id) {
        $msg = $plugin->translate("Mail form setting '[_1]' (ID:[_2]) created by '[_3]'.", $setting->title, $setting->id, $app->user->name);
        $category = 'new';
    }
    else {
        $msg = $plugin->translate("Mail form setting '[_1]' (ID:[_2]) edited by '[_3]'.", $setting->title, $setting->id, $app->user->name);
        $category = 'edit';
    }
    $app->log({
        message => $msg,
        class => 'mailform',
        category => $category,
        blog_id => $blog_id,
        level => MT::Log::INFO(),
    });

    # redirect
    $app->redirect(
        $app->uri(mode => 'fjmf_do_setting',
                  args => { 'id' => $setting->id,
                            'blog_id' => $blog_id,
                            'saved' => 1 }));
}

sub post_delete {
    my ($eh, $app, $setting) = @_;
    my $plugin = MT->component('mailform');

    $app->log({
            message => $plugin->translate(
                "Mail form setting '[_1]' (ID:[_2]) deleted by '[_3]'.",
                $setting->title, $setting->id, $app->user->name
            ),
            level    => MT::Log::INFO(),
            class    => 'mailform',
            category => 'delete'
    });
}

sub insert_tag {
    my $app = shift;
    my $plugin = MT->component('mailform');
    my %params;

    # check permission
    my $perms = $app->permissions
        or return $app->error($plugin->translate('Load permission error'));
    return $app->error($plugin->translate('You have no permission'))
        unless ($perms->can_administer_blog);

    # load template
    my $blog_id = $app->param('blog_id');
    my $tmpl_id = $app->param('id');
    my $i_tmpl = MT::Template->load({ blog_id => $blog_id,
                                    id => $tmpl_id });
    if ($i_tmpl) {
        my $text = $i_tmpl->text;
#        my $title = MT::I18N::encode_text($app->param('title'), 'utf8', $app->charset);
        my $title = $app->param('title');
        my $required_tag = '<MTSetVar name="mail_setting" value="' . $title . '">';
        if ($text =~ /(<[Mm][Tt]:?[Ss][Ee][Tt][Vv][Aa][Rr].*?name\s*=\s*['"]mail_setting['"].*?>)/) {
            my $old = $1;
            my $new = $old;
            $new =~ s/(value\s*=\s*['"])[^'"]*(['"])/$1$title$2/;
            if ($new ne $old) {
                $old = quotemeta($old);
                $text =~ s/$old/$new/;
                $params{modified} = 1;
            }
        }
        else {
            $text = $required_tag . "\n" . $text;
            $params{inserted} = 1;
        }
        if ($params{modified} || $params{inserted}) {
            $i_tmpl->text($text);
            $i_tmpl->save;
            $params{required_tag} = encode_html($required_tag);
            $params{tmpl} = $text;
        }
        else {
            $params{not_changed} = 1;
        }
    }
    else {
        $params{error} = 1;
        $params{not_changed} = 1;
    }

    # show page
    my $tmpl = $plugin->load_tmpl('insert_tag.tmpl');
    $tmpl->text($plugin->translate_templatized($tmpl->text));
    $app->build_page($tmpl, \%params);
}

sub rebuild {
    my $app = shift;
    my $plugin = MT->component('mailform');
    my %params;

    # check permission
    my $perms = $app->permissions
        or return $app->error($plugin->translate('Load permission error'));
    return $app->error($plugin->translate('You have no permission'))
        unless ($perms->can_administer_blog);

    # load template
    my $blog_id = $app->param('blog_id');
    my $tmpl_id = $app->param('id');
    my $i_tmpl = MT::Template->load({ blog_id => $blog_id,
                                    id => $tmpl_id });
    my $result = $app->rebuild_indexes( BlogID => $blog_id,
                                        Template => $i_tmpl,
                                        Force => 1 );

    # show page
    my $tmpl = $plugin->load_tmpl('rebuild_mail_form.tmpl');
    $params{result} = $result;
    $params{err_msg} = $app->errstr if (!$result);
    $tmpl->text($plugin->translate_templatized($tmpl->text));
    $app->build_page($tmpl, \%params);
}

sub install_template_setup {
    my $app = shift;
    my $plugin = MT->component('mailform');
    my %params;

    # check permission
    my $perms = $app->permissions
        or return $app->error($plugin->translate('Load permission error'));
    return $app->error($plugin->translate('You have no permission'))
        unless ($perms->can_administer_blog);

    # load template sets
    my $blog_id = $app->param('blog_id');
    $params{blog_id} = $blog_id;
    my $template_sets_path = $plugin->path . "/template_sets";
    my (@tmpl_sets, @set_files);
    opendir DH, $template_sets_path
        or return $app->error($plugin->translate('Open directory error'));
    while (my $name = readdir DH) {
        next if ($name !~ /\.yaml$/);
#        my $yaml = YAML::Tiny->new;
        require MT::Util::YAML;
        my $yaml = eval { MT::Util::YAML::LoadFile("${template_sets_path}/${name}"); }
            or return $app->error($plugin->translate('Load YAML error'));

        push @set_files, { order => $yaml->{order},
                           sets => $yaml->{sets} };
    }
    @set_files = sort { $a->{order} <=> $b->{order} } @set_files;
    for my $set_file (@set_files) {
        for my $set (@{$set_file->{sets}}) {
            push @tmpl_sets, { dir => $set->{dir},
                               name => $set->{name} };
        }
    }

    # set template params
    $params{tmpl_sets} = \@tmpl_sets;
    $params{form_template}    = $plugin->translate('Mail Form');
    $params{preview_template} = $plugin->translate('Preview');
    $params{error_template}   = $plugin->translate('Error');
    $params{post_template}    = $plugin->translate('Post');
    $params{body_template}    = $plugin->translate('Body');
    $params{reply_template}   = $plugin->translate('Reply');
    $params{common_template}  = $plugin->translate('Common module of mail form');
    $params{outfile} = 'mailform.html';
    $params{position_actions_bottom} = 1;

    # show page
    my $tmpl = $plugin->load_tmpl('install_template_setup.tmpl');
    $tmpl->text($plugin->translate_templatized($tmpl->text));
    $app->build_page($tmpl, \%params);
}

sub install_template {
    my $app = shift;
    my $plugin = MT->component('mailform');
    my %params;

    $app->validate_magic() or return;

    # check permission
    my $perms = $app->permissions
        or return $app->error($plugin->translate('Load permission error'));
    return $app->error($plugin->translate('You have no permission'))
        unless ($perms->can_administer_blog);

    # initialize
    my $blog_id = $app->param('blog_id');
    my $dir = $app->param('template_set');
    my $path = $plugin->path . "/template_sets/" . $dir . "/";

    # get name of template set
    my $template_sets_path = $plugin->path . "/template_sets";
    opendir DH, $template_sets_path
        or return $app->error($plugin->translate('Open directory error'));
    my %tmpl_sets;
    while (my $name = readdir DH) {
        next if ($name !~ /\.yaml$/);
#        my $yaml = YAML::Tiny->new;
#        $yaml = YAML::Tiny->read("${template_sets_path}/${name}")
#            or return $app->error($plugin->translate('Load YAML error'));
        require MT::Util::YAML;
        my $yaml = eval { MT::Util::YAML::LoadFile("${template_sets_path}/${name}"); }
            or return $app->error($plugin->translate('Load YAML error'));
        for my $sets (@{$yaml->{sets}}) {
            $tmpl_sets{$sets->{dir}} = $sets->{name};
        }
    }

    # check template names
    my $is_exist_error = 0;
    my $is_noname_error = 0;
    my @exist_tmpls = ();
    my @noname_tmpls = ();
    my @names = qw( form preview error post body reply common );
    for my $name (@names) {
        my $tmpl_param = "${name}_template";
        my $tmpl_name = $app->param($tmpl_param);
        if ($tmpl_name) {
            $tmpl_name = 'mail_' . $name . ':' . $tmpl_name;
            my $type = ($name eq 'form') ? 'index' : 'custom';
            my $count = MT::Template->count({ blog_id => $blog_id,
                                              name => $tmpl_name,
                                              type => $type });
            if ($count) {
                $is_exist_error = 1;
                push @exist_tmpls, { tmpl_name => $tmpl_name };
            }
        }
        else {
            $is_noname_error = 1;
            push @noname_tmpls, { tmpl_name => $plugin->translate(($name eq 'form') ? 'Mail Form' : ucfirst($name)) };
        }
    }
    $params{is_exist_error} = $is_exist_error;
    $params{exist_tmpls} = \@exist_tmpls;
    $params{is_noname_error} = $is_noname_error;
    $params{noname_tmpls} = \@noname_tmpls;
    $params{is_redo} = $is_exist_error || $is_noname_error;

    # install templates
    my $is_load_error = 0;
    my $is_create_error = 0;
    my $is_created = 0;
    my (@load_error_tmpls, @create_error_tmpls, @created_tmpls);

    if (!$params{is_redo}) {
        my $blog = MT::Blog->load($blog_id);
        my $fmgr = $blog->file_mgr;
        my $form_tmpl;
        for my $name (@names) {
            my $tmpl_param = "${name}_template";
            my $tmpl_name = $app->param($tmpl_param);
            $tmpl_name = 'mail_' . $name . ':' . $tmpl_name;
            my $file_name = "${path}mail_${name}.mtml";
            my $text = $fmgr->get_data($file_name);
            if (defined($text)) {
                $text = MT::I18N::encode_text($text, 'utf8', $app->charset);
                my $type = ($name eq 'form') ? 'index' : 'custom';
                my $tmpl = MT::Template->new;
                $tmpl->blog_id($blog_id);
                $tmpl->name($tmpl_name);
                $tmpl->type($type);
                $tmpl->text($text);
                if ($name eq 'form') {
                    $tmpl->rebuild_me(1);
                    $tmpl->outfile($app->param('outfile'));
                }
                if ($tmpl->save) {
                    $is_created = 1;
                    push @created_tmpls, { tmpl_name => $tmpl_name };
                }
                else {
                    $is_create_error = 1;
                    push @create_error_tmpls, { tmpl_name => $tmpl_name };
                }
            }
            else {
                $is_load_error = 1;
                push @load_error_tmpls, { tmpl_name => $plugin->translate(($name eq 'form') ? 'Mail Form' : ucfirst($name)) };
            }
        }
    }
    $params{is_load_error} = $is_load_error;
    $params{load_error_tmpls} = \@load_error_tmpls;
    $params{is_create_error} = $is_create_error;
    $params{create_error_tmpls} = \@create_error_tmpls;
    $params{is_created} = $is_created;
    $params{created_tmpls} = \@created_tmpls;

    # save log
    if (!$is_load_error) {
        $app->log({
            message => $plugin->translate("Template set '[_1]' for mail form installed by '[_2]'.", $tmpl_sets{$dir}, $app->user->name),
            class => 'mailform',
            category => 'mail_template_installed',
            blog_id => $blog_id,
            level => MT::Log::INFO(),
        });
    }

    # show page
    my $tmpl = $plugin->load_tmpl('install_template.tmpl');
    $tmpl->text($plugin->translate_templatized($tmpl->text));
    $app->build_page($tmpl, \%params);
}

sub restore {
    my ($cb, $objects, $deferred, $errors, $callback) = @_;
    my (%blogs, %authors, %tmpls, @settings);

    for my $key (keys %$objects) {
        if ($key =~ /^MT::Blog#(\d+)$/) {
            $blogs{$1} = $objects->{$key}->id;
        }
        elsif ($key =~ /^MT::Author#(\d+)$/) {
            $authors{$1} = $objects->{$key}->id;
        }
        elsif ($key =~ /^MT::Template#(\d+)$/) {
            $tmpls{$1} = $objects->{$key}->id;
        }
        elsif ($key =~ /^MailForm::Setting#(\d+)$/) {
            push @settings, $objects->{$key};
        }
    }

    for my $setting (@settings) {
        $setting->blog_id($blogs{$setting->blog_id});
        $setting->author_id($authors{$setting->author_id});
        for my $tmpl (qw ( form preview error post common body reply )) {
            my $field = $tmpl . '_template_id';
            $setting->column($field, $tmpls{$setting->column($field)});
        }
        $setting->save;
    }

    1;
}

1;
