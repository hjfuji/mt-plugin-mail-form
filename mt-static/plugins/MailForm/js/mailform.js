var FJAjaxMail = {};

FJAjaxMail.send = function(mode) {
    $('#mail_preview').attr({ disabled : true });
    $('#mail_post').attr({ disabled : true });
    var params = $('#mail_form').serialize();
    $('#ajax_mail').html(FJAjaxMail.waitMsg);
    if (mode == "post") {
        params += "&mail_post=1";
    }
    else if (mode == "preview") {
        params += "&mail_preview=1";
    }

    $.ajax({
        type : 'post',
        url : FJAjaxMail.cgiPath + 'plugins/MailForm/mt-mail-form.cgi',
        data : params,
        success : function(html) {
            $("#ajax_mail").html(html);
        },
        error : function(html) {
            $('#ajax_mail').html(FJAjaxMail.failureMsg);
//            $('#send_status').style.display = 'none';
        }
    });
    location.hash = 'ajax_mail';
    return false;
};
