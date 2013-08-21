package MailForm::Tags;

use strict;
use MailForm::Setting;
use MT::Util qw( html_text_transform encode_js );

# MTMailPreviewAuthor tag
sub mail_preview_author
{
    my ($ctx, $args) = @_;

    my $value = $ctx->stash('mail_author');
    $value = '' unless(defined($value));
    return $value;
}

# MTMailPreviewEMail tag
sub mail_preview_email
{
    my ($ctx, $args) = @_;

    my $value = $ctx->stash('mail_email');
    $value = '' unless(defined($value));
    return $value;
}

# MTMailPreviewEMailConfirm tag
sub mail_preview_email_confirm
{
    my ($ctx, $args) = @_;

    my $value = $ctx->stash('mail_email_confirm');
    $value = '' unless(defined($value));
    return $value;
}

# MTMailPreviewSubject tag
sub mail_preview_subject
{
    my ($ctx, $args) = @_;

    my $value = $ctx->stash('mail_subject');
    $value = '' unless(defined($value));
    return $value;
}

# MTMailPreviewBody tag
sub mail_preview_body
{
    my ($ctx, $args) = @_;

    my $value = $ctx->stash('mail_body');
    $value = '' unless(defined($value));
    if ($args->{convert_breaks} == 1) {
        $value = html_text_transform($value);
    }
    return $value;
}

# MTMailPreviewExtParam tag
sub mail_preview_ext_param
{
    my ($ctx, $args) = @_;

    my $ext_params = $ctx->stash('mail_ext_params');

    my $value = $ext_params->{$args->{name}};
    $value = '' unless(defined($value));
    if ($args->{convert_breaks} == 1) {
        $value = html_text_transform($value);
    }
    return $value;
}

# MTMailFormAjaxJS tag
sub mail_form_ajax_js
{
    my ($ctx, $args) = @_;
    my $plugin = MT->component('mailform');

    my $builder = $ctx->stash('builder');
    my $setting = $ctx->stash('mail_setting');
    if (!$setting) {
        my $setting_title = $ctx->var('mail_setting');
        $setting = MailForm::Setting->load({ blog_id => $ctx->stash('blog_id'),
                                             title => $setting_title })
            or return $ctx->error($plugin->translate('Mail form setting load error'));
        $ctx->stash('mail_setting', $setting);
    }
    my $cgipath = $ctx->tag('CGIPath', $args);
    my $static_path = $ctx->tag('StaticWebPath', $args);
    my $wait_tok = $builder->compile($ctx, $setting->wait_msg);
    my $wait_msg = $builder->build($ctx, $wait_tok)
        or return $ctx->error($plugin->translate('Build error in wait message'));
    $wait_msg = encode_js($wait_msg);
    my $error_tok = $builder->compile($ctx, $setting->error_msg);
    my $error_msg = $builder->build($ctx, $error_tok)
        or return $ctx->error($plugin->translate('Build error in process error message'));
    $error_msg = encode_js($error_msg);
    my $out = '';
    if (!$args->{no_jquery}) {
        $out = <<HERE;
<script type="text/javascript" src="${static_path}jquery/jquery.js"></script>

HERE
    }
    $out .= <<HERE;
<script type="text/javascript" src="${static_path}plugins/MailForm/js/mailform.js"></script>
<script type="text/javascript">
//<![CDATA[
FJAjaxMail.cgiPath = '$cgipath';
FJAjaxMail.waitMsg = '$wait_msg';
FJAjaxMail.errorMsg = '$error_msg';
//]]>
</script>

HERE
    return $out;
}

# MTMailPreviewIfEmailError tag
sub mail_preview_if_error
{
    my ($ctx, $args) = @_;


    $ctx->stash('is_mail_error') &&
    return ($ctx->var('mail_is_error_page') || $ctx->stash('mail_do_error_check'));
}

# MTMailPreviewIfInputError tag
sub mail_preview_if_input_error
{
    my ($ctx, $args) = @_;


    $ctx->stash('is_input_error') &&
    return ($ctx->var('mail_is_error_page') || $ctx->stash('mail_do_error_check'));
}

# MTMailPreviewIfFieldError tag
sub mail_preview_if_field_error
{
    my ($ctx, $args) = @_;

    my $error_fields = $ctx->stash('mail_error_fields');
    $error_fields->{$args->{name}} == 1 &&
    return ($ctx->var('mail_is_error_page') || $ctx->stash('mail_do_error_check'));
}

# MTMailPreviewIfEmailError tag
sub mail_preview_if_email_error
{
    my ($ctx, $args) = @_;

    $ctx->stash('is_mail_invalid') &&
    return ($ctx->var('mail_is_error_page') || $ctx->stash('mail_do_error_check'));
}

# MTMailPreviewIfEmailDifferent tag
sub mail_preview_if_email_different
{
    my ($ctx, $args) = @_;

    $ctx->stash('is_mail_different') &&
    return ($ctx->var('mail_is_error_page') || $ctx->stash('mail_do_error_check'));
}

# MTMailPreviewIfNotChecked tag
sub mail_preview_if_not_checked
{
    my ($ctx, $args) = @_;

    my $not_checked_fields = $ctx->stash('not_checked_fields');
    $not_checked_fields->{$args->{name}} == 1 &&
    return ($ctx->var('mail_is_error_page') || $ctx->stash('mail_do_error_check'));
}

# MTMailIfAutoReplyError tag
sub mail_if_auto_reply_error
{
    my ($ctx, $args) = @_;

    return $ctx->stash('is_auto_reply_error');
}

# MTMailIfSendError tag
sub mail_if_send_error
{
    my ($ctx, $args) = @_;

    return $ctx->stash('is_send_error');
}

# MTMailIfThrottled tag
sub mail_if_throttled
{
    my ($ctx, $args) = @_;

    return $ctx->stash('is_throttled');
}

# MTMailIfIPBanned tag
sub mail_if_ipbanned
{
    my ($ctx, $args) = @_;

    return $ctx->stash('is_ipbanned');
}

# MTMailIfSpam tag
sub mail_if_spam
{
    my ($ctx, $args) = @_;

    return $ctx->stash('is_spam');
}

# MTMailIfSystemTemplate tag
sub mail_if_system_template
{
    my ($ctx, $args) = @_;

    return $ctx->stash('mail_is_system');
}

# MTMailBodyContainer tag
sub mail_body_container
{
    my ($ctx, $args, $cond) = @_;

    my $builder = $ctx->stash('builder');
    my $tokens  = $ctx->stash('tokens');

    $ctx->stash('mail_unencode', 1);
    defined(my $body = $ctx->stash('builder')->build($ctx, $ctx->stash('tokens'), $cond))
        or return $ctx->error($builder->errstr);
    $ctx->stash('mail_unencode', undef);
    return $body;
}

# MTMailErrors tag

# MTIncludeMailFormCommon tag
sub include_mail_form_common {
    my ($ctx, $args, $cond) = @_;
    my $plugin = MT->component('mailform');

    my $setting = $ctx->stash('mail_setting');
    my $blog = $ctx->stash('blog');
    if (!$setting) {
        my $setting_title = $ctx->var('mail_setting');
        $setting = MailForm::Setting->load({ title => $setting_title, blog_id => $blog->id })
            or return $ctx->error($plugin->translate('Mail form setting load error'));
        $ctx->stash('mail_setting', $setting);
    }
    my $common_tmpl_id = $setting->common_template_id;
    my $common_tmpl = MT::Template->load($common_tmpl_id);
    $args->{module} = $common_tmpl->name;
    my $out = $ctx->tag('Include', $args, $cond);
    return $out;
}

sub mail_form_plugin_version {
    my ($ctx, $args) = @_;
    my $plugin = MT->component('mailform');
    return $plugin->{version};
}

1;
