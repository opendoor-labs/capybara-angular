module Capybara
  module Angular
    class Waiter
      attr_accessor :page

      def initialize(page)
        @page = page
        @setup_ready_count = 0
      end

      def wait_until_ready
        return unless angular_app?

        setup_ready
        @setup_ready_count += 1

        start = Time.now
        until ready?
          timeout! if timeout?(start)
          if page_reloaded_on_wait?
            return unless angular_app?
            setup_ready
            @setup_ready_count += 1
          end
          sleep(0.01)
        end
      end

      private

      def timeout?(start)
        Time.now - start > Capybara::Angular.default_max_wait_time
      end

      def timeout!
        raise TimeoutError.new("timeout while waiting for angular #{@setup_ready_count}" + page.driver.network_traffic.select { |t| t.response_parts.empty? }.map(&:inspect).join("\n\n"))
      end

      def ready?
        page.evaluate_script("window.angularReady")
      end

      def angular_app?
        js = "(typeof angular !== 'undefined') && "
        js += "angular.element(document.querySelector('[ng-app], [data-ng-app]')).length > 0"
        page.evaluate_script js

      rescue Capybara::NotSupportedByDriverError
        false
      end

      def setup_ready
        page.execute_script <<-JS
          // TODO(edward): this is so questionable combined with the sleep and the notifyWhenNoOutstandingRequests
          // there should be a single reference
          window.angularReady = window.angularReady || false;

          if ((typeof angular === 'undefined') || angular.element(document.querySelector('[ng-app], [data-ng-app]')).length == 0)
            return;

          var el = document.querySelector('[ng-app], [data-ng-app]');

          function ready(fn) {
            if (document.readyState !== 'loading'){
              fn();
            } else if (document.addEventListener) {
              document.addEventListener('DOMContentLoaded', fn);
            } else {
              document.attachEvent('onreadystatechange', function() {
                if (document.readyState !== 'loading')
                  fn(); // TODO(edward): does this only happen once? does the readyState only go from loading -> something else?
              });
            }
          }

          ready(function () {
            if (angular.getTestability) {
              angular.getTestability(el).whenStable(function() { window.angularReady = true; });
            } else {
              var $browser = angular.element(el).injector().get('$browser');

              if ($browser.outstandingRequestCount > 0) { window.angularReady = false; }
              $browser.notifyWhenNoOutstandingRequests(function() { window.angularReady = true; });
            }
          });

        JS
      end

      def page_reloaded_on_wait?
        page.evaluate_script("window.angularReady === undefined")
      end
    end
  end
end
