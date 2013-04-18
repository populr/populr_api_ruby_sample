'use strict';

/* Directives */

// Source: https://github.com/angular/angular.js/issues/1277
// @arcanis

module = angular.module('myApp.directives', [])
module.directive( [ 'focus', 'blur', 'keyup', 'keydown', 'keypress' ].reduce( function ( container, name ) {
    var directiveName = 'ng' + name[ 0 ].toUpperCase( ) + name.substr( 1 );

    container[ directiveName ] = [ '$parse', function ( $parse ) {
        return function ( scope, element, attr ) {
            var fn = $parse( attr[ directiveName ] );
            element.bind( name, function ( event ) {
                scope.$apply( function ( ) {
                    fn( scope, {
                        $event : event
                    } );
                } );
            } );
        };
    } ];

    return container;
}, { } ) );


// This makes any element droppable
// Usage: <div droppable></div>
module.directive('droppable', ['$compile', function($compile) {
  return {
    restrict: 'A',
    link: function(scope,element,attrs){
        filepicker.constructWidget($(element));
    }
  };
}]);

