'use strict';

/* Controllers */

angular.module('myApp.controllers', []).
  controller('MyCtrl1', ['$scope', 'Templates', 'Pops', function($scope, Templates, Pops) {

    $scope.api_key = 'UXXMOCJW-BKSLPCFI-UQAQFWLO';
    $scope.selected_template = null;
    $scope.pop_data = {tags: {}, regions: {}};
    $scope.pop_slug = ''
    $scope.pop_errors = {tags: {}, regions: {}};
    $scope.creating = false;

    $scope.fetch_templates = function() {
      Templates.index({api_key:$scope.api_key}, function(templates){
        $scope.templates = templates
      });
    }

    $scope.fetch_templates()

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

    $scope.class_for_region_input = function(region) {
      if ($scope.pop_errors.regions[region])
        return 'error';
      return '';
    }

    $scope.select_template = function(template) {
      $scope.selected_template = template;
    }

    $scope.files_selected = function(region, files) {
      var urls = []
      for (var i = 0; i < files.length; i++){
        urls.push(files[i].url);
      }
      $scope.pop_data.regions[region] = urls
    }

    $scope.sanitize_slug = function() {
      $scope.pop_slug = $scope.pop_slug.replace(/ /g, '-')
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
        slug: $scope.pop_slug,
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

      for (var i = 0; i < $scope.selected_template.api_regions.length; i++) {
        var region = $scope.selected_template.api_regions[i];
        var unfilled = (!$scope.pop_data.regions[region] || $scope.pop_data.regions[region].length == 0)
        $scope.pop_errors.regions[region] = unfilled
        error = unfilled || error
      }

      if (!$scope.$$phase)
        $scope.$apply()
      return !error;
    }

  }])

  .controller('MyCtrl2', [function() {

  }]);
