## Populr API — Pop Builder Sample App ('Populate')

The Pop Builder sample app allows you to see the templates in your account and perform common tasks without building a custom application on top of the API. Two primary use cases are currently supported:

1. You want users to fill out a form and receive a pop (either a published pop with an opitonal password, a clone link, or a collaboration link). The form may be embedded within a pop or used independently.

2. You want to create a large number of pops using a specific template and a table of data.

Each of these use cases is explained in further detail below.

### Getting Started

 The app is written in Sinatra, uses AngularJS on the front-end, and uses Filepicker.io to enable image/file uploads. If you are interested in running your own copy of Populate:

1. Check out the source, `cd` into the project directory and run:

    `bundle`

    `rackup -p 5000`

2. Open [http://localhost:5000](http://localhost:5000) in a browser.

3. Select 'localhost' from the enviornments dropdown on the left.

4. VVERBOSE=1 QUEUE=pop_task bundle exec rake resque:work


Then, to get started as a user:

1. If you haven't already, visit [Populr.me](http://Populr.me) and register for API access. If you have API access, the Group Settings page will show your Populr API key.

2. If you haven't already, create a pop template on Populr.me by following the instructions in the [developer documentation](http://developers.populr.me).

3. Paste your API key into the top left of the Populate web page. Your templates should appear in the left sidebar.

4. Click one and choose one of the actions in the top menu that appears.


-----

### Peforming Common Tasks

#### Creating a Pop Form

A pop form is a simple web form that is automatically generated by Populate based on the tags and regions you've defined in your template. For example, let's say I have a Populr template for a birthday party. It includes the tags [Party Address] and [Party Name]. It also includes an image asset region that I've called 'Party Photos'. When I use the Populate app to generate a form, that form will include areas for providing those three pieces of data.

When you create a Pop Form, you'll need to select a delivery action. The available options are explained below:

#####Delivery Actions:


1. **Publish the Pop:** When they've completed the form, a pop will be automatically created and published. The user will be redirected to their new pop in the browser.  If you check the email delivery box, they will also receive a Populate-branded email with their pop's URL.
	2. **Password Protection:** If you enable email delivery, you can also enable a password, which is randomly generated and assigned. The password will be sent in the pop email, unless you choose the two factor authentication option. When using two-factor authentiction, the pop link is delivered via email, while the pop's password is delivered via SMS. This ensures the greatest level of security.


	 
2. **Invite to Clone:** When they've completed the form, the user will be redirected to Populr, where they can create an account and continue editing the pop in **their own account**. If you check the email delivery box, they will also receive a Populate-branded email with a URL they can use to create a Populr account and continue editing later.

	*Note: This method is designed for scenarios where you don't need to track what users do with the pops they create. Once the user clones the pop they've created, you can't see changes that are made or control how/when the pop is published.*


	 
3. **Invite to Collaborate:** When they've completed the form, the user will be redirected to Populr, where they can create an account to continue editing the pop in **your account**. If you check the email delivery box, they will also receive a Populate-branded email with a URL they can use to create a Populr account and continue editing later.

	*Note: This method is great if you want to allow users to edit their pops after they've filled out the form, but you want to maintain ownership and publishing rights. Using this method, users are able to customize their pages and add content, but they cannot publish or delete their pages.*

####Bulk Import from CSV

Populate's bulk import feature allows you to create a large number of pops very quickly. You can chose to download the URLs/passwords to the pops that are generated and distribute them on your own, or you can allow Populate to deliver an email for each pop that is created.

#####Bulk Import Step-by-Step:

1. Identify the fields that you want to customize in each of your pops. That could include the name of a product, a person's name, pictures and documents, and more. Make sure that the template you're using contains API template regions and API tags for each of these fields.

2. Visit the Populate website and follow the instructions at the top of this guide to connect to your account. Select the template from the sidebar and then choose "Bulk Import from CSSV" from the top menu.
3. Click the "Download" button. Populate will look at the fields available in the template and provide you with a CSV file you can fill in. It is important that the fields are in the correct order, so you should always use the CSV file provided by Populate.

4. Open the CSV file and take a look at the fields. You should have one field for each of the API regions and tags in your pop. Add a row to the CSV file for each pop you want to create.

 		If you'd like to place documents or images in your pops, the documents must be available on the web already (though they may be on a server that is not publicized.) Place the file URL, or file multiple URLs separated with commas, into the appropriate cell in the CSV file. Once Populate runs, the files will be hosted securely at Populr and you can take down the copies you posted on the web for Populate.

		The "Recipient Email" and "Recipient Phone" fields are optional. If you do not provide an email address for a row, no notification will be sent for that pop.

5. Save your changes to the CSV file.
5. On the Bulk Import page, click "Choose File" and select the CSV file you saved. Choose one of the 	delivery actions (described above) and type your email address.
6. Click "Process Job"

You will receive an email from Populate when your pops have been created. The email contains a link to the CSV file you provided with two columns appended to the end. One for each pop's password, and another for each pop's URL. Depending on the delivery action you chose, this might be the URL of the published pop, or a URL a user could use to collaborate on or clone the pop.

If errors occurred while processing your pops, an error will be shown in the output CSV file. You should remove the rows that were processed successfully, fix the issues that prevented the failed pops from being generated, and run just those through Populate again.

### Contributing

Pull requests are welcome. Please file issues if you discover any problems!