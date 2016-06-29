<?php
require_once('class.mt_mailform_setting.php');

function smarty_function_mtmailformtitle($args, &$ctx) {
    $setting = $ctx->stash('mail_setting');
    $blog = $ctx->stash('blog');
    $blog_id = $blog->id;
    if (!$setting) {
        $setting_title = $ctx->__stash['vars']['mail_setting'];
        $_setting = new MailFormSetting;
        $where = <<< HERE
mailform_setting_blog_id = ${blog_id}
AND mailform_setting_title = '${setting_title}'
HERE;
        $extras['limit'] = 1;
        $setting = $_setting->Find($where, false, false, $extras);

        if (count($setting)) {
            $setting = $setting[0];
            $ctx->stash('mail_setting', $setting);
        }
    }
    if (isset($setting)) {
        return $setting->title;
    }
    else {
        return '';
    }
}
?>
