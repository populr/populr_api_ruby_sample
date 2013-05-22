/* Controllers */

angular.module('myApp.controllers', []).
  controller('MainController', ['$scope', 'Templates', 'Embeds', 'Pops', function($scope, Templates, Embeds, Pops) {
    $scope.api_key = 'UXXMOCJW-BKSLPCFI-UQAQFWLO';
    $scope.selected_template = null;
    $scope.selected_template_pops = [];
    $scope.selected_tab = 'create';
    $scope.selected_embed = null;
    $scope.show_environments = window.location.href.indexOf('localhost') != -1
    $scope.environments = [{name: 'production'},{name: 'staging'},{name: 'localhost'}]

    $scope.fetch_templates = function() {
      Templates.index({api_key:$scope.api_key, api_env: $scope.env.name}, function(templates){
        $scope.templates = templates
      });
    }

    $scope.popul8_url = function() {
      return window.location.href.substr(0, window.location.href.indexOf('/index'));
    }

    $scope.select_environment = function(option) {
      $scope.env = option;
      $scope.selected_template = null;
      $scope.selected_embed = null;
      $scope.selected_template_pops = [];
      $scope.fetch_templates();
    }

    $scope.class_for_template = function(template) {
      if ($scope.selected_template == template)
        return 'todo-done';
      return '';
    }

    $scope.select_template = function(template) {
      $scope.selected_template = template;
      $scope.selected_embed = {};
      $scope.selected_template_pops = [];
      Pops.index({api_key:$scope.api_key, api_env: $scope.env.name, template_id: template._id}, function(pops) {
        $scope.selected_template_pops = pops;
      });
    }

    $scope.create_embed = function() {
      Embeds.create({
        api_key: $scope.api_key,
        api_env: $scope.env.name,
        action: $scope.selected_embed.action,
        confirmation: $scope.selected_embed.confirmation,
        password_enabled:  $scope.selected_embed.password_enabled,
        password_sms_enabled: $scope.selected_embed.password_sms_enabled,
        template_id: $scope.selected_template._id
      }, function (embed) {
        if (embed.error)
          return alert(embed.error)
        else {
          $scope.selected_embed = embed;
        }
      });
    }

    $scope.validate_csv_form = function() {
      if ((!$scope.csv_email) || ($scope.csv_email.length == 0))
          return false;
      return true;
    }

    $scope.select_environment($scope.environments[0]);

  }]);
