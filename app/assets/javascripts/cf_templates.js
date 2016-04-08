//
// Copyright (c) 2013-2016 SKYARCH NETWORKS INC.
//
// This software is released under the MIT License.
//
// http://opensource.org/licenses/mit-license.php
//

(function() {

  //browserify functions for vue filters functionality
  var wrap = require('./modules/wrap');
  var listen = require('./modules/listen');
  var queryString = require('query-string').parse(location.search);
  var ace = require('brace');
  require('brace/theme/github');
  require('brace/mode/json');

  var modal       = require('modal');

  var app;

  Vue.component('demo-grid', require('demo-grid.js'));

  var editor;
  $(document).ready(function(){

    if ($('#description').length > 0) {
      editor = ace.edit("description");
      var textarea = $('#cf_template_value');
      editor.getSession().setValue(textarea.val());
      editor.getSession().on('change', function(){
        textarea.val(editor.getSession().getValue());
      });
      editor.setOptions({
        maxLines: 30,
        minLines: 15,
      });
      editor.setTheme("ace/theme/github");
      editor.getSession().setMode("ace/mode/json");
      $("#ace-loading").hide();
    }
  });

  var cf_templatesIndex = new Vue({
    el: '#indexElement',
    data: {
      searchQuery: '',
      gridColumns: ['subject','details'],
      gridData: [],
      index: 'cf_templates',
      picked: {
        button_destroy_cft: null,
        button_edit_cft: null
      }
    },
    methods: {
      can_edit: function() {
        return (this.picked.button_edit_cft === null);
      },
      can_delete: function() {
        return (this.picked.button_destroy_cft === null);
      },
      delete_entry: function()  {
        var delete_project_url = this.picked.button_destroy_cft;
        modal.Confirm(t('cf_templates.cf_template'), t('cf_templates.msg.delete_cf_template'), 'danger').done(function () {
          $.ajax({
            type: "POST",
            url: delete_project_url,
            dataType: "json",
            data: {"_method":"delete"},
          });
          event.preventDefault();
          location.reload();
        });
      },
      show_template: function(cf_template_id) {
        $.ajax({
          url : "/cf_templates/" + cf_template_id,
          type : "GET",
          success : function (data) {
            $("#template-information").html(data);
          }
        }).done(function () {
          var viewer = ace.edit('cf_value');
          viewer.setOptions({
            maxLines: Infinity,
            minLines: 15,
            readOnly: true
          });
          viewer.setTheme("ace/theme/github");
          viewer.getSession().setMode("ace/mode/json");
        });
      }
    }
  });


  $(document).on("click", ".show-template", function () {
    var cf_template_id = $(this).closest("a").attr("data-managejson-id");
    var tr = $(this).closest('tr');
    $('tr.info').removeClass('info');
    tr.addClass('info');


  });
})();
