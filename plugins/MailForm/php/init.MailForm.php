<?php
require_once('fjot_registry.php');
require_once('function.mtmailformurl.php');
require_once('function.mtmailformtitle.php');

$mt = MT::get_instance();
$ctx = &$mt->context();

fjot_init_registry($ctx);

fjot_set_registry(
    $ctx, 'obj_class_libs', array(
        'mailform_setting' => 'mt_mailform_setting',
    )
);

fjot_set_registry(
    $ctx, 'models', array(
        'mailform_setting' => 'MailFormSetting',
    )
);

fjot_set_registry(
    $ctx, 'id_columns', array(
        'mailform_setting' => 'mailform_setting_id',
    )
);

fjot_set_registry(
    $ctx, 'stash_classes', array(
        'mailform_setting' => 'mail_setting',
    )
);

fjot_set_registry(
    $ctx, 'tree_tags', array(
        'mailform_setting' => array(
            'label' => function($ctx, $args) {
                return $ctx->tag('mailformtitle', $args);
            },
            'link' => function($ctx, $args) {
                return $ctx->tag('mailformurl', $args);
            },
            'exclude' => function($setting) { return 0; },
            'blog_children' => 1
        )
    )
);
?>
