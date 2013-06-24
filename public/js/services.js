'use strict';

/* Services */


// Demonstrate how to register services
// In this case it is a simple value service.
var module = angular.module('myApp.services', ['ngResource'])
var templates = function($resource) {
  return $resource('/_/templates/:id', {}, {index: { method: 'GET', isArray: true, params:{api_key:'@api_key', api_env:'@api_env'}}, get: { method: 'GET', params:{api_key:'@api_key', api_env:'@api_env'}} })
}
var embeds = function($resource) {
  return $resource('/_/embeds/:embed', {}, {create: {method: 'POST'}})
}
var pops = function($resource) {
  return $resource('/_/pops', {}, {index: { method: 'GET', isArray: true, params: {api_key:'@api_key', api_env:'@api_env', template_id: '@template_id'}}, create: {method: 'POST'}, update: { method: 'PUT' }, destroy: { method: 'DELETE' }})
}
var jobs = function($resource) {
  return $resource('/_/jobs', {}, {index: { method: 'GET', isArray: true, params: {api_key:'@api_key', api_env:'@api_env', template_id: '@template_id'}}, create: {method: 'POST'}, update: { method: 'PUT' }, destroy: { method: 'DELETE' }})
}

module.value('version', '0.1');
module.factory('Templates', ['$resource', templates])
module.factory('Pops', ['$resource', pops])
module.factory('Jobs', ['$resource', jobs])
module.factory('Embeds', ['$resource', embeds])

