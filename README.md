## Populr API — Pop Builder Sample App

The Pop Builder sample app allows you to see the templates in your account and create a new pop by filling out a form that is dynamically generated based on the tags and regions you defined in the template. It's written in Sinatra, uses AngularJS on the front-end, and uses Filepicker.io to enable image/file uploads.

#### Getting Started

1. Check out the source, `cd` into the project directory and run:

    `bundle`
    
    `rackup -p 5000`

2. Open [http://localhost:5000](http://localhost:5000) in a browser.

3. If you haven't already, visit [Populr.me](http://Populr.me) and register for API access. If you have API access, your Group Settings page will show your Populr API key.

4. If you haven't already, create a pop template on Populr.me by following the instructions in the [developer documentation](http://developers.populr.me).

5. Paste your API key into the top left of the demo app's web page.

6. Select the environment you're using, if it's not production.

7. Your template should appear in the left sidebar. Click it and fill out the form to create a pop!


#### Contributing

Pull requests are welcome. Please file issues if you discover any problems!