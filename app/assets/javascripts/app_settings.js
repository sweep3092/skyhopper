//
// Copyright (c) 2013-2016 SKYARCH NETWORKS INC.
//
// This software is released under the MIT License.
//
// http://opensource.org/licenses/mit-license.php
//

(function () {
  "use strict";
  var modal = require('modal');

  //  ----------------------------- variables



  var endpoint_base = '/app_settings';
  var inputs_selector = '#app-settings-form input[type=text],input[type=password],select,textarea';
  var required_inputs = '#app-settings-form input[required],select[required],textarea[required]';


  //  -------------------------------- ajax methods
  var create = function () {
    var settings = get_settings();
    settings = remove_empty_optional_params(settings);

    return $.ajax({
      url: endpoint_base,
      type: 'POST',
      data: {
        settings: JSON.stringify(settings)
      },
    }).fail(function (xhr) {
      var res = xhr.responseJSON;
      var kind = res.error.kind;
      if (kind.endsWith('VpcIDNotFound')) {
        modal.AlertHTML(kind, t('app_settings.msg.vpc_id_not_found', {id: _.escape(settings.vpc_id)}), 'danger');
      } else if (kind.endsWith('SubnetIDNotFound')) {
        modal.AlertHTML(kind, t('app_settings.msg.subnet_id_not_found', {id: _.escape(settings.subnet_id)}), 'danger');
      } else if (kind.endsWith('SystemServerError')) {
        modal.AlertHTML(kind, res.error.message, 'danger');
      }else {
        modal.AlertForAjaxStdError()(xhr);
      }
    });
  };

  var chef_create = function () {
    var stack_name = $('#chef_stack_name').val();

    return $.ajax({
      url: endpoint_base + '/chef_create',
      type: 'POST',
      data: {
        stack_name: stack_name,
      },
      dataType: "json",

    }).fail(modal.AlertForAjaxStdError());
  };


  //  --------------------------------  utility methods
  var get_settings = function () {
    var settings = {};
    $(inputs_selector).each(function () {
      var input = $(this);
      var key = input.attr('name');
      var val = input.val();
      settings[key] = val;
    });
    return settings;
  };

  var remove_empty_optional_params = function (obj) {
    var optional_keys = ['vpc_id', 'subnet_id'];
    optional_keys.forEach(function (key) {
      if (obj[key] === '') {
        delete obj[key];
      }
    });
    return obj;
  };

  var is_fill_required_input = function () {
    var elements = document.querySelectorAll(required_inputs);
    for (var i = 0; i < elements.length; ++i) {
      if (elements[i].value === '') {
        return false;
      }
    }
    return true;
  };


  //  inputが全部埋まっていれば btn をenableにする。
  //  全部埋まっていなければdisableにする
  var switch_btn_enable = function (btn) {
    if (is_fill_required_input()) {
      btn.removeAttr('disabled');
    } else {
      btn.attr('disabled', 'disabled');
    }
  };


  var watch_chef_create_progress = function () {
    // TODO
    $('#btn-create-chefserver').hide();
    $('.create-chefserver').show();


    var ws = ws_connector('chef_server_deployment', 'status');
    ws.onmessage = function (msg) {
      var parsed = JSON.parse(msg.data);

      update_creating_chefserver_progress(parsed);
    };
  };


  var update_creating_chefserver_progress = function (data) {
    var progress       = $("#progress-create-chefserver");
    var progress_bar   = progress.children(".progress-bar");
    var progress_alert = $("#alert-create-chefserver");
    var current_percentage = parseInt( progress_bar.attr("area-valuenow") );

    progress_alert.text(data.message);
    // 進捗していればプログレスバーを進める
    if (data.percentage !== null && parseInt(data.percentage) > current_percentage ) {
      progress_bar.attr("style", "width: " + data.percentage + "%").attr("area-valuenow", data.percentage);
    }

    if (data.status === "complete") {
      progress.removeClass("progress-bar-striped active");
      progress_bar.removeClass("progress-bar-info").addClass("progress-bar-success");
      progress_alert.removeClass("alert-info").addClass("alert-success");

      $("#done-appsetting").removeClass("disabled").removeAttr("disabled");
    }
    else if (data.status === "error") {
      progress.removeClass("progress-bar-striped active");
      progress_bar.removeClass("progress-bar-info").addClass("progress-bar-danger");
      progress_alert.removeClass("alert-info").addClass("alert-danger");
    }
  };



  //  ----------------------------- event binding


  $(document).on('click', '#btn-create-chefserver', function (e) {
    e.preventDefault();

    create().done(function (data) {
      chef_create().done(function (data) {
        update_creating_chefserver_progress(data);
        watch_chef_create_progress();
      });
    });
  });


  $(document).on('change keyup', required_inputs, function () {
    var btn = $('#btn-create-chefserver');
    switch_btn_enable(btn);
  });


  $(document).on('click', '#btn-show-optional-inputs', function (e) {
    e.preventDefault();

    $('#btn-show-optional-inputs').hide();
    $('#optional-inputs').fadeIn('fast');
  });

})();
