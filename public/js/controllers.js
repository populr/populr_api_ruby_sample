/* Controllers */

angular.module('myApp.controllers', []).
  controller('MyCtrl1', ['$scope', 'Templates', 'Pops', function($scope, Templates, Pops) {

    $scope.api_key = 'UXXMOCJW-BKSLPCFI-UQAQFWLO';
    $scope.selected_template = null;
    $scope.selected_template_pops = [];

    $scope.pop_data = {slug: '', tags: {}, file_regions: {}, embed_regions: {}};
    $scope.pop_errors = {tags: {}, file_regions: {}, embed_regions: {}};
    $scope.creating = false;
    $scope.selected_tab = 'create';

    $scope.environments = [{name: 'production'},{name: 'staging'},{name: 'localhost'}]
    $scope.env = $scope.environments[0];

    $scope.fetch_templates = function() {
      Templates.index({api_key:$scope.api_key, api_env: $scope.env.name}, function(templates){
        $scope.templates = templates
      });
    }

    $scope.fetch_templates()

    $scope.select_environment = function(option) {
      $scope.env = option;
      $scope.fetch_templates();
    }

    $scope.class_for_template = function(template) {
      if ($scope.selected_template == template)
        return 'todo-done';
      return '';
    }

    $scope.class_for_tag_input = function(tag) {
      if ($scope.pop_errors.tags[tag])
        return 'error';
      return '';
    }

    $scope.class_for_region_input = function(region_key) {
      if ($scope.pop_errors.file_regions[region_key])
        return 'error';
      return '';
    }

    $scope.select_template = function(template) {
      $scope.selected_template = template;
      Pops.index({api_key:$scope.api_key, api_env: $scope.env.name, template_id: template._id}, function(pops) {
        $scope.selected_template_pops = pops;
      });
    }

    $scope.files_selected = function(region_key, files) {
      var urls = []
      for (var i = 0; i < files.length; i++){
        urls.push(files[i].url);
      }
      $scope.pop_data.file_regions[region_key] = urls
    }

    $scope.sanitize_slug = function() {
      $scope.pop_data['slug'] = $scope.pop_data['slug'].replace(/ /g, '-')
    }

    $scope.create_pop = function() {
      if (!$scope.selected_template)
        return;

      if (!$scope.check_form_valid()) {
        return alert('Please fill in all of the fields.');
      }

      $scope.creating = true;

      Pops.create({
        api_key: $scope.api_key,
        api_env: $scope.env.name,
        pop_data: $scope.pop_data,
        template_id: $scope.selected_template._id
      }, function (pop) {
        $scope.creating = false;
        if (pop.error)
          return alert(pop.error)
        else {
          window.location = pop.published_pop_url
        }
      });
    }

    $scope.check_form_valid = function() {
      var error = false;
      for (var i = 0; i < $scope.selected_template.api_tags.length; i++) {
        var tag = $scope.selected_template.api_tags[i];
        var unfilled = (!$scope.pop_data.tags[tag] || $scope.pop_data.tags[tag].length == 0)
        $scope.pop_errors.tags[tag] = unfilled
        error = unfilled || error
      }

      var region_keys = Object.keys($scope.selected_template.api_regions);
      for (var i = 0; i < region_keys.length; i++) {
        var key = region_keys[i];
        var attributes = $scope.selected_template.api_regions[key];

        if (attributes['type'] == 'embed') {
          var unfilled = (!$scope.pop_data.embed_regions[key] || $scope.pop_data.embed_regions[key].length == 0)
          $scope.pop_errors.embed_regions[key] = unfilled
        } else {
          var unfilled = (!$scope.pop_data.file_regions[key] || $scope.pop_data.file_regions[key].length == 0)
          $scope.pop_errors.file_regions[key] = unfilled
        }
        error = unfilled || error
      }

      if (!$scope.$$phase)
        $scope.$apply()
      return !error;
    }

  }])

  .controller('MyCtrl2', [function() {

  }]);
