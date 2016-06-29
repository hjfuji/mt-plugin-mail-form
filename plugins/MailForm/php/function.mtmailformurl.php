<?php
require_once('class.mt_mailform_setting.php');
require_once('class.mt_template.php');

function smarty_function_mtmailformurl($args, &$ctx) {
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
        $localvars = array('index_templates', 'index_templates_counter');
        $ctx->localize($localvars);
        $tmpls = $ctx->mt->db()->fetch_templates(array(
            type => 'index',
            blog_id => $ctx->stash('blog_id')
        ));
        $ctx->stash('index_templates', $tmpls);
        $url = '';
        for ($i = 0; $i < count($tmpls); $i++) {
            if ($tmpls[$i]->id == $setting->form_template_id) {
                $ctx->stash('index_templates_counter', $i);
                $url = $ctx->tag('indexlink', $args);
                break;
            }
        }
        $ctx->restore($localvars);
        return $url;
    }
    else {
        return '';
    }
}
?>
