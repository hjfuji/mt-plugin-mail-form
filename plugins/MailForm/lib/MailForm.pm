#
# MailForm.pm
# 2006/03/05 1.00 First Release
# 2006/06/14 1.10 Version up
# 2006/10/18 1.11 For Ajax
# 2007/01/23 1.20 Version up
# 2007/01/27 1.20.1 Bug fix(XSS)
# 2007/05/   1.30 Version up (for spam)
# 2008/01/10 2.00 Renewal for MT4
# 2008/05/03 2.10 Add function
# 2009/09/25 2.20 Renewal for MT5
# 2009/12/07 2.20b2 add pre_build_mail callback to sending rmail
# 2011/05/19 2.30b1 For Movable Type 5.1
#
# Copyright(c) by H.Fujimoto
#
package MailForm;
use base qw(MT::App);
use strict;

use MT;

#use constant LANGUAGE => 'ja';
#use constant MAIL_POST_TEMPLATE => 'mail_post';
#use constant MAIL_PREVIEW_TEMPLATE => 'mail_preview';
#use constant MAIL_ERROR_TEMPLATE => 'mail_error';
use constant THROTTLE_SECONDS => 60;

use MT::Mail;
use MT::I18N;
use MT::ConfigMgr;
use MT::Template;
use MT::Template::Context;
use MT::Util qw( is_valid_email remove_html encode_html epoch2ts );
use MT::Log;
use MT::IPBanList;
use MT::Comment;
use MT::JunkFilter qw(:constants);
use MailForm::Setting;

sub init
{
    my $app = shift;
    $app->SUPER::init(@_) or return;
    $app->add_methods(
        post => \&post,
    );
    $app->{default_mode} = 'post';
    $app->{charset} = $app->{cfg}->PublishCharset;
    $app;
}

#sub plugin {
#    MT::Plugin::MailForm->instance;
#}

#sub translate_templatized {
#    my $app = shift;
#    $app->plugin->translate_templatized(@_);
#}

sub post
{
    my $app = shift;
    my $plugin = MT->component('mailform');

    my (@errmsg, $from, $data, %head, %rhead, $iter);
    my $mail_log;
    my $iserror = 0;
    my $is_input_error = 0;
    my $is_auto_reply_error = 0;
    my $is_throttled = 0;
    my $is_ipbanned = 0;
    my $is_spam = 0;
    my $is_must_check_error = 0;
    my $is_mail_invalid_error = 0;
    my $is_mail_different_error = 0;
    my $is_send_error = 0;
    my $mgr = $app->{cfg}->instance;
    my $enc = $mgr->PublishCharset || 'utf-8';
    my $mail_enc = $mgr->MailEncoding || 'iso-8859-1';

    # load setting
    my $ajax = $app->param('mail_ajax');
    my $setting_title = $app->param('mail_setting');
    $setting_title = &_encode_ajax($setting_title, $ajax);
    my $blog_id = $app->param('mail_blog_id');
    my $setting = MailForm::Setting->load({ blog_id => $blog_id,
                                            title => $setting_title });
    return $app->error($plugin->translate('Load setting error'))
        if (!$setting);
    my $tmail = $setting->email_to;
    my $tmail2 = $setting->email_to2;
    my $tmail_cc = $setting->email_cc;
    my $tmail_bcc = $setting->email_bcc;
    my $tmail_from = $setting->email_from;
    my $tmail_type = $setting->email_from_type;
    my $msubject = $setting->mail_subject;
    my $rmail = $setting->rmail_from;
    my $rsend = $setting->auto_reply;
    my $rsubject = $setting->reply_subject;
    my $is_email_confirm = $setting->email_confirm;
    my $error_check_fields_str = $setting->error_check_fields;
    my $must_check_fields_str  = $setting->must_check_fields;
    my $error_specific_check_str = $setting->error_specific_check;
    my $preview_template = $setting->preview_template_id;
    my $post_template    = $setting->post_template_id;
    my $error_template   = $setting->error_template_id;
    my $body_template    = $setting->body_template_id;
    my $reply_template   = $setting->reply_template_id;

    # set language
    MT->set_language($setting->language || $app->config('DefaultLanguage'));

    # get query parameter
    my $body    = $app->param('mail_text');
    $body       = &_encode_ajax($body, $ajax);
    my $email   = $app->param('mail_email');
    $email      = &_encode_ajax($email, $ajax);
    my $email_confirm = $app->param('mail_email_confirm');
    $email_confirm    = &_encode_ajax($email_confirm, $ajax);
    my $author  = $app->param('mail_author');
    $author     = &_encode_ajax($author, $ajax);
    my $subject = $app->param('mail_subject');
    $subject    = &_encode_ajax($subject, $ajax);
    my $preview = $app->param('mail_preview') ||
                  defined($app->param('mail_preview_x')) ||
                  defined($app->param('mail_preview.x'));
    my $post    = $app->param('mail_post') ||
                  defined($app->param('mail_post_x')) ||
                  defined($app->param('mail_post.x'));
    my @params = $app->param;
    my %ext_params;
    my ($ext_params_str, $ext_params_tmp);
    for my $param (@params) {
        next if ($param eq 'mail_blog_id' || $param eq 'mail_setting' ||
                 $param eq 'mail_email' || $param eq 'mail_email_confirm' ||
                 $param eq 'mail_text' || $param eq 'mail_author' ||
                 $param eq 'mail_subject' ||
                 $param eq 'mail_preview' || $param eq 'mail_post');
        $ext_params_tmp = &_encode_ajax($app->param($param), $ajax);
        $ext_params{$param} = $ext_params_tmp;
        $ext_params_str .= $ext_params_tmp . "\n";
    }

    # error check
    $iserror = 0;
    @errmsg = ();
    my %error_check_fields;
    map { $error_check_fields{$_} = 1; } split(',', $error_check_fields_str);
    my %error_specific_check_fields;
    for my $line (split("\n", $error_specific_check_str)) {
        my @data = split(',', $line);
        my %values;
        for (my $ctr = 1; $ctr < scalar(@data); $ctr++) {
            $values{$data[$ctr]} = 1;
        }
        $error_specific_check_fields{$data[0]} = \%values;
    }
    my %error_fields = ();
    if ($subject eq '') {
        if ($error_check_fields{mail_subject}) {
            $iserror = 1;
            $is_input_error = 1;
            push @errmsg, $plugin->translate('Input mail subject.');
            $error_fields{mail_subject} = 1;
        }
        else {
            $subject = $plugin->translate('(No title)');
        }
    }

    if (!$email && (!%error_check_fields ||
                    $error_check_fields{mail_email})) {
        $iserror = 1;
        $is_input_error = 1;
        push @errmsg, $plugin->translate('Input your mail address.');
        $error_fields{mail_email} = 1;
    }
    elsif(!is_valid_email($email) &&
       (!%error_check_fields ||
        $error_check_fields{mail_email})) {
        $iserror = 1;
        $is_input_error = 1;
        push @errmsg, $plugin->translate('Mail address is invalid.');
        $is_mail_invalid_error = 1;
    }
    if ($is_email_confirm && $email ne $email_confirm) {
        $iserror = 1;
        $is_input_error = 1;
        push @errmsg, $plugin->translate('Confirmation mail addresses isdifferent from mail address.');
        $is_mail_different_error = 1;
    }
    if (!$author && (!%error_check_fields ||
                     $error_check_fields{mail_author})) {
        $iserror = 1;
        $is_input_error = 1;
        push @errmsg, $plugin->translate('Input your name.');
        $error_fields{mail_author} = 1;
    }

    if (!$body && (!%error_check_fields ||
                   $error_check_fields{mail_text})) {
        $iserror = 1;
        $is_input_error = 1;
        push @errmsg, $plugin->translate('Input mail body.');
        $error_fields{mail_text} = 1;
    }
    for my $error_check_field (keys %error_check_fields) {
        if (defined($ext_params{$error_check_field}) &&
            $ext_params{$error_check_field} eq '') {
            $iserror = 1;
            $is_input_error = 1;
            $error_fields{$error_check_field} = 1;
            push @errmsg, $plugin->translate('Input field [_1].', $error_check_field);
        }
    }
    for my $error_check_field (keys %error_specific_check_fields) {
        my $value = $ext_params{$error_check_field};
        if ($value &&
            $error_specific_check_fields{$error_check_field} &&
            $error_specific_check_fields{$error_check_field}->{$value}) {
            $iserror = 1;
            $is_input_error = 1;
            $error_fields{$error_check_field} = 1;
            push @errmsg, $plugin->translate('Input field [_1].', $error_check_field);
        }
    }

    # check must check fields
    my (%must_check_fields, %not_checked_fields);
    map { $must_check_fields{$_} = 1; } split(',', $must_check_fields_str);
    for my $must_check_field (keys %must_check_fields) {
        if (!defined($app->param($must_check_field))) {
            $iserror = 1;
            $is_input_error = 1;
            $not_checked_fields{$must_check_field} = 1;
            push @errmsg, $plugin->translate('Field [_1] is not checked.', $must_check_field);
        }
    }

    my $blog = MT::Blog->load($blog_id)
                   or return $app->error("load blog error");

    # throttle check
    if (!$preview && !$iserror) {
        my $from_ts = epoch2ts(undef, time - THROTTLE_SECONDS);
        $iter = MT::Log->load_iter({ blog_id => $blog_id,
                                     class => 'mailform',
                                     created_on => [ $from_ts ] },
                                   { range => { created_on => 1 }});
        while (my $log = $iter->()) {
            if ($log->ip == $app->remote_ip && $log->category eq 'mail_sent') {
                $iserror = 1;
                $is_throttled = 1;
                push @errmsg, $plugin->translate('Too many mails have been submitted from you in a short period of time.  Please try again in a short while.');            last;
            }
        }
    }

    # ip banning
    if (!$preview && !$iserror) {
        $iter = MT::IPBanList->load_iter({ blog_id => $blog_id });
        while (my $ban = $iter->()) {
            my $banned_ip = $ban->ip;
            if ($app->remote_ip =~ /$banned_ip/) {
                $iserror = 1;
                $is_ipbanned = 1;
                push @errmsg, $plugin->translate("You are not allowed to send mail.");
                last;
            }
        }
    }

    # spam check
    if (!$preview && !$iserror) {
        my $text = $subject . "\n" . $body . "\n" . $ext_params_str;
        $text = '' unless defined $text;
        $text =~ tr/\r//d;
        my $mdata = MT::Comment->new;
        $mdata->ip($app->remote_ip);
        $mdata->blog_id($blog_id);
        $mdata->entry_id(0);
        $mdata->author(remove_html($author));
        $mdata->email(remove_html($email));
        $mdata->url('');
        $mdata->text($text);
        $mdata->junk_status(0);
        MT::JunkFilter->filter($mdata);
        if ($mdata->is_junk ||
            (defined($mdata->visible) && !$mdata->visible)) {
            $iserror = 1;
            $is_spam = 1;
            push @errmsg, $plugin->translate("Your email is not allowed to send because of spam check.");
        }
    }

    # store data for callbacks
    my %mail_data;
    $mail_data{body}          = \$body;
    $mail_data{email}         = \$email;
    $mail_data{email_confirm} = \$email_confirm;
    $mail_data{author}        = \$author;
    $mail_data{subject}       = \$subject;
    $mail_data{ext_params}    = \%ext_params;
    $mail_data{setting}       = $setting;

    # additional error check callback
    my $additional_errors = {};
    my $add_is_error = $app->run_callbacks('MailForm.add_error_check', $app, \%mail_data, $setting, $additional_errors, \@errmsg);
    $iserror = 1 if (!$add_is_error);

    # send mail
    if (!$iserror && !$preview) {
        # set initialize data
        my $ctx = MT::Template::Context->new;
        my %cond;
        $ctx->stash('blog', $blog);
        $ctx->stash('blog_id', $blog_id);
        $ctx->stash('mail_body', $body);
        $ctx->stash('mail_email', $email);
        $ctx->stash('mail_author', $author);
        $ctx->stash('mail_subject', $subject);
        $ctx->stash('mail_ext_params', \%ext_params);
        for my $param (keys %ext_params) {
            $ctx->var($param, $ext_params{$param});
        }
        $app->run_callbacks('MailForm.pre_build_mail', $app, \%mail_data, $setting, $ctx);

        # make mail body
        my $mail_body;
        if ($body_template) {

            # build mail template
            my $tmpl = MT::Template->load({ id => $body_template,
                                            type => 'custom',
                                            blog_id => $blog_id })
                or return $app->error($plugin->translate('Mail Body Template load error'));
            $mail_body = $tmpl->build($ctx, \%cond);
            return $app->error($tmpl->errstr) unless(defined($mail_body));
        }
        else {
            $mail_body = $plugin->translate("Subject : [_1]\nAuthor : [_2] <[_3]>\nMail body :\n[_4]", $subject, $author, $email, $body);
            if (keys %ext_params) {
                $mail_body .= $plugin->translate('Extra fields :') . "\n";
                for my $param (keys %ext_params) {
                    $mail_body .= $param . " = " . $ext_params{$param} . "\n";
                }
            }
            if ($rsend && !$email) {
                 $mail_body .= $plugin->translate("\nAuto reply has not done because of mail address was not input.\n");
            }
        }

        # make reply mail body
        my $rctx = MT::Template::Context->new;
        my %rcond;
        $rctx->stash('blog', $blog);
        $rctx->stash('blog_id', $blog_id);
        $rctx->stash('mail_body', $body);
        $rctx->stash('mail_email', $email);
        $rctx->stash('mail_author', $author);
        $rctx->stash('mail_subject', $subject);
        $rctx->stash('mail_ext_params', \%ext_params);
        for my $param (keys %ext_params) {
            $rctx->var($param, $ext_params{$param});
        }
        $app->run_callbacks('MailForm.pre_build_rmail', $app, \%mail_data, $setting, $rctx);

        my $reply_body;
        if ($reply_template) {
            # build reply mail template
            my $tmpl = MT::Template->load({ id => $reply_template,
                                            type => 'custom',
                                            blog_id => $blog_id })
                or return $app->error($plugin->translate("Mail Reply Template load error"));
            $reply_body = $tmpl->build($rctx, \%rcond);
            return $app->error($tmpl->errstr) unless(defined($reply_body));
        }
        else {
             $reply_body = $plugin->translate("Dear [_1]\n\nThank you for emailing to me.\n(This mail is auto reply.)", $author);
        }

        # build reply subject template
        my $rstmpl = MT::Template->new;
        $rstmpl->text($rsubject);
        my $reply_subject = $rstmpl->build($rctx, \%rcond);

        # send mail
        if ($tmail_type) {
            $head{From} = $tmail_from;
            $head{'Reply-To'} = $email;
        }
        else {
            $head{From} = $email;
        }
        my (@tmail, @tmail_cc, @tmail_bcc);
        push @tmail, $tmail;
        push @tmail, split(',', $tmail2) if ($tmail2);
        @tmail_cc = split(',', $tmail_cc);
        @tmail_bcc = split(',', $tmail_bcc);
        my $mgr = MT->config->MailTransfer;
        if ($mgr eq 'smtp' && MT->version_number lt '5.2') {
            $head{To} = join ', ', @tmail;
        }
        else {
            $head{To} = \@tmail;
        }
        $head{Cc} = \@tmail_cc if ($tmail_cc);
        $head{Bcc} = \@tmail_bcc if ($tmail_bcc);
        my $mtmpl = MT::Template->new;
        $mtmpl->text($msubject);
        my $mail_subject = $mtmpl->build($ctx, \%cond);
        $head{Subject} = $mail_subject || $plugin->translate('Sent mail from mail form.');
        $app->run_callbacks('MailForm.pre_mail_send', $app, \%mail_data, $setting, \%head);
        eval {
            MT::Mail->send(\%head, $mail_body) or die("Mail Error");
        };

        if ($@) {
            $iserror = 1;
            $is_send_error = 1;
            push @errmsg, $plugin->translate('Sending mail failed.');
            $app->run_callbacks('MailForm.post_mail_send', $app, \%mail_data, $setting, 0);
        }
        else {
            $mail_log = $plugin->translate('Sent mail from mail form.');
            $app->run_callbacks('MailForm.post_mail_send', $app, \%mail_data, $setting, 1);
        }

        # send reply mail
        if ($rsend && $email) {
            $rhead{To} = $email;
            $rhead{From} = $rmail;
            $rhead{Subject} = $reply_subject || $plugin->translate('Thank you for emailing me.');
            $app->run_callbacks('MailForm.pre_rmail_send', $app, \%mail_data, $setting, \%rhead);
            eval {
                MT::Mail->send(\%rhead, $reply_body) or die("Mail Error");
            };
            if ($@) {
                $is_auto_reply_error = 1;
                push @errmsg, $plugin->translate('Sending mail failed.');
                $app->run_callbacks('MailForm.post_rmail_send', $app, \%mail_data, $setting, 0);
            }
            else {
                $mail_log .= $plugin->translate('(and auto reply)');
                $app->run_callbacks('MailForm.post_rmail_send', $app, \%mail_data, $setting, 1);
            }
        }
    }

    # save send log
    if (!$preview && !$iserror) {
        $app->log({
            message => $mail_log,
            class => 'mailform',
            category => 'mail_sent',
            blog_id => $blog_id,
            level => MT::Log::INFO(),
        });
        $app->run_callbacks('MailForm.processed', $app, \%mail_data, $setting);
    }

    # set initialize data
    my $ctx = MT::Template::Context->new;
    my %cond;
    my %ext_params_encoded;
    for my $param (keys %ext_params) {
        $ctx->var($param, $ext_params{$param});
        $ext_params_encoded{$param} = encode_html($ext_params{$param});
    }
    $ctx->stash('blog', $blog);
    $ctx->stash('blog_id', $blog_id);
    $ctx->stash('mail_body', encode_html($body));
    $ctx->stash('mail_email', encode_html($email));
    $ctx->stash('mail_email_confirm', encode_html($email_confirm));
    $ctx->stash('mail_author', encode_html($author));
    $ctx->stash('mail_subject', encode_html($subject));
    $ctx->stash('mail_ext_params', \%ext_params_encoded);
    $ctx->stash('mail_error_fields', \%error_fields);
    $ctx->stash('not_checked_fields', \%not_checked_fields);
    $ctx->stash('error_message', join('<br />', @errmsg));
    $ctx->stash('error_message_array', \@errmsg) if ($iserror);
    $ctx->stash('is_mail_error', $iserror);
    $ctx->stash('is_input_error', $is_input_error);
    $ctx->stash('is_send_error', $is_send_error);
    $ctx->stash('is_auto_reply_error', $is_auto_reply_error);
    $ctx->stash('is_throttled', $is_throttled);
    $ctx->stash('is_ipbanned', $is_ipbanned);
    $ctx->stash('is_spam', $is_spam);
    $ctx->stash('is_mail_invalid', $is_mail_invalid_error);
    $ctx->stash('is_mail_different', $is_mail_different_error);
    $ctx->stash('mail_is_system', 1);
    $ctx->stash('mail_setting', $setting);
    $ctx->stash('mail_do_error_check', $setting->error_check_in_preview);
    $ctx->var('system_template', 1);
    $ctx->var('mail_system_template', 1);
    $ctx->var('mail_is_system', 1);
    $ctx->var('mail_is_error', $iserror);
    $ctx->var('mail_is_error_page', ($iserror && !$preview));
    $ctx->var('mail_is_preview_page', $preview);
    $ctx->var('mail_is_post_page', (!$preview && !$iserror));
    $ctx->var('mail_setting', $setting_title);
    $app->run_callbacks('MailForm.pre_show_page', $app, \%mail_data, $setting, $additional_errors, \@errmsg, $ctx);

    # load template
    my $tmpl_id;
    if ($preview) {
        if ($iserror && $setting->error_check_in_preview &&
            $setting->preview_error_template eq 'error') {
            $tmpl_id = $error_template;
            $ctx->var('mail_error_template', 1);
        }
        else {
            $ctx->stash('error_message', '')
                if (!$setting->error_check_in_preview);
            $tmpl_id = $preview_template;
            $ctx->var('mail_preview_template', 1);
        }
    }
    elsif ($iserror) {
        $tmpl_id = $error_template;
        $ctx->var('mail_error_template', 1);
    }
    else {
        $tmpl_id = $post_template;
        $ctx->var('mail_post_template', 1);
    }

    # build template
    my $tmpl = MT::Template->load({ id => $tmpl_id,
                                    type => 'custom',
                                    blog_id => $blog_id });
    if (!$tmpl) {
        if ($preview) {
            return $app->error($plugin->translate('Preview template load error'));
        }
        elsif ($iserror) {
            return $app->error($plugin->translate('Error template load error'));
        }
        else {
            return $app->error($plugin->translate('Post template load error'));
        }
    }
    my $html = $tmpl->build($ctx, \%cond);
    return $app->error($tmpl->errstr) unless(defined($html));

#    if ($ajax) {
#        $html = MT::I18N::encode_text($html, $enc, 'utf-8');
#        $html = "\xef\xbb\xbf" . $html;
#    }
    $app->{no_print_body} = 1;
    if ($ajax) {
        $app->send_http_header('text/html; charset=utf-8');
    }
    else {
        if ($ctx->stash('content_type')) {
            $app->send_http_header($ctx->stash('content_type'));
        }
        else {
            $app->send_http_header('text/html; charset=' . $app->{charset});
        }
    }
    $app->print_encode($html);
}

sub _encode_ajax
{
    my ($str, $ajax) = @_;

#    if ($ajax) {
#        my $enc = MT::ConfigMgr->instance->PublishCharset;
#        $str = MT::I18N::encode_text($str, 'utf-8', $enc);
#    }
    $str =~ s/\r\n/\n/sg;
    $str =~ s/\r/\n/sg;
    $str;
}

1;
