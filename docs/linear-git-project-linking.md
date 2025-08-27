Option 1: Repository-Project Linking (Recommended)

  Linear allows you to link GitHub/GitLab repositories to specific projects. This is the most
  robust approach:

  1. In Linear UI: Go to Project Settings → Integrations → Link your repository
  2. Query via API: Use the repository connection to filter issues

  query GetProjectIssuesForRepo($repoUrl: String!) {
    projects(filter: {
      repositories: {
        some: { url: { eq: $repoUrl } }
      }
    }) {
      nodes {
        id
        issues(first: 20, filter: { assignee: { id: { eq: "current_user_id" } } }) {
          nodes {
            id
            identifier
            title
            state { name }
            priority
          }
        }
      }
    }
  }

  Option 2: Git Remote Detection + Project Mapping

  If repository linking isn't set up, we can:

  1. Auto-detect git remote: git config --get remote.origin.url
  2. Map to Linear project: Store mapping in config or detect via project name matching

  Option 3: Project Filtering by Name/Key

  Use git repository name to match Linear project:

  query GetProjectIssuesByName($projectKey: String!) {
    projects(filter: { key: { eq: $projectKey } }) {
      nodes {
        issues(first: 20, filter: { assignee: { id: { eq: "current_user_id" } } }) {
          nodes { ... }
        }
      }
    }
  }
