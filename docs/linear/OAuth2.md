# OAuth 2.0 authentication

Linear supports OAuth2 authentication, which is recommended if you’re building applications to integrate with Linear.

> [!NOTE]
> It is **highly recommended** you create a workspace for the purpose of managing the OAuth2 Application, as each admin user will have access.

## Create an OAuth2 application

Create a new [OAuth2 Application](https://linear.app/settings/api/applications/new) and configure the redirect callback URLs to your application.

## Redirect user access requests to Linear

When authorizing a user to the Linear API, redirect to an authorization URL with correct parameters and scopes:

```http
GET https://linear.app/oauth/authorize HTTP/1.1
```

Name | Description
--- | ---
`client_id` | (required) Client ID provided when you create the OAuth2 Application
`redirect_uri` | (required) Redirect URI
`response_type=code` | (required) Expected response type
`scope` | (required) Comma separated list of scopes:

* `read` - (Default) Read access for the user's account. This scope will always be present.
* `write` - Write access for the user's account. If your application only needs to create comments, use a more targeted scope
* `issues:create` - Allows creating new issues and their attachments
* `comments:create` - Allows creating new issue comments
* `timeSchedule:write` - Allows creating and modifying time schedules
* `admin` - Full access to admin level endpoints. You should never ask for this permission unless it's absolutely needed
`state` | (optional) Prevents CSRF attacks and should always be supplied. Read more about it [here](https://auth0.com/docs/protocols/state-parameters)
`prompt=consent` | (optional) The consent screen is displayed every time, even if all scopes were previously granted. This can be useful if you want to give users the opportunity to connect multiple workspaces.
`actor` | Define how the OAuth application should create issues, comments and other changes:

* `user` - (Default) Resources are created as the user who authorized the application. This option should be used if you want each user to do their own authentication
* `app` - Resources are created as the application. This option should be used for agents and service accounts or agents.

### Example

```http
GET https://linear.app/oauth/authorize?response_type=code&client_id=YOUR_CLIENT_ID&redirect_uri=YOUR_REDIRECT_URL&state=SECURE_RANDOM&scope=read HTTP/1.1

GET https://linear.app/oauth/authorize?client_id=client1&redirect_uri=http%3A%2F%2Flocalhost%3A3000%2Foauth%2Fcallback&response_type=code&scope=read,write HTTP/1.1
```

## Handle the redirect URLs you specified in the OAuth2 Application

Once the user approves your application they will be redirected back to your application, with the OAuth authorization `code` in the URL params.

Any `state` parameter you specified in step 2 will also be returned in the URL params and must match the value specified in step 2. If the values do not match, the request should not be trusted.

### Example

```http
GET https://example.com/oauth/callback?code=9a5190f637d8b1ad0ca92ab3ec4c0d033ad6c862&state=b1ad0ca92 HTTP/1.1
```

## Exchange ,`code`, for an access token

After receiving the `code`, you can exchange it for a Linear API access token:

```http
POST https://api.linear.app/oauth/token HTTP/1.1
```

> [!NOTE]
> Pass parameters in body as [URL-encoded form submission](https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods/POST#url-encoded_form_submission), where the `Content-Type` header must be `application/x-www-form-urlencoded`.

Parameter | Description
--- | ---
`code` | (required) Authorization code from the previous step
`redirect_uri` | (required) Same redirect URI which you used in the previous step
`client_id` | (required) Application's client ID
`client_secret` | (required) Application's client secret
`grant_type=authorization_code` | (required)

### Response

After a successful request, a valid access token will be returned in the response:

```json
{
  "access_token": "00a21d8b0c4e2375114e49c067dfb81eb0d2076f48354714cd5df984d87b67cc",
  "token_type": "Bearer",
  "expires_in": 315705599,
  "scope": "read write"
}
```

> [!NOTE]
> Note: OAuth apps created prior to Dec 1, 2023 will instead return `scope` as an array of strings in the token response.

## Make an API request

Once you have obtained a valid access token, you can make a request to Linear's GraphQL API. You can initialize the [Linear Client](https://linear.app/developers/sdk) with the access token:

```typescript
const client = new LinearClient({ accessToken: response.access_token })
const me = await client.viewer
```

Or pass the token as an authorization header: `Authorization: Bearer <ACCESS_TOKEN>`

```sh
curl https://api.linear.app/graphql \
  -X POST \
  -H "Content-Type: application/json" \
  -H 'Authorization: Bearer <ACCESS_TOKEN>' \
  --data '{ "query": "{ viewer { id name } }" }' \
```

## Revoke an access token

To revoke a user's access to your application pass the access token as Bearer token in the authorization header (`Authorization: Bearer <ACCESS_TOKEN>`) or as the `access_token` form field:

```http
POST https://api.linear.app/oauth/revoke HTTP/1.1
```

### Response

Expected HTTP status:

* `200` - token was revoked
* `400` - unable to revoke token (e.g. token was already revoked)
* `401` - unable to authenticate with the token
