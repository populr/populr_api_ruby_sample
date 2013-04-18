'use strict';

/* Services */


// Demonstrate how to register services
// In this case it is a simple value service.
var module = angular.module('myApp.services', ['ngResource'])
var templates = function($resource) {
  return $resource('/_/templates', {}, {index: { method: 'GET', isArray: true, params:{api_key:'@api_key'}}, update: { method: 'PUT' }, destroy: { method: 'DELETE' }})
}

var pops = function($resource) {
  return $resource('/_/pops', {}, {index: { method: 'GET', isArray: true, params: {api_key:'@api_key'}}, create: {method: 'POST'}, update: { method: 'PUT' }, destroy: { method: 'DELETE' }})
}

module.value('version', '0.1');
module.factory('Templates', ['$resource', templates])
module.factory('Pops', ['$resource', pops])
