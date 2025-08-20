# Nexus.nvim - High-Level Implementation Plan

```
     ███╗   ██╗███████╗██╗  ██╗██╗   ██╗███████╗
     ████╗  ██║██╔════╝╚██╗██╔╝██║   ██║██╔════╝
     ██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║███████╗
     ██║╚██╗██║██╔══╝   ██╔██╗ ██║   ██║╚════██║
     ██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝███████║
     ╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝
     
     [ The Developer's Mission Control Center ]
```

## Alternative ASCII Logo (Compact):
```
    ╱◣ NEXUS ◢╲
   ╱◢◣______◢◣╲
  ▕ ◢◣ ╱╲╱╲ ◢◣ ▏
  ▕◢◣ ╱◢◣◢◣╲ ◢◣▏
   ╲◣╱◢◣  ◢◣╲◢╱
    ╲◣______◢╱
```

## Core Architecture

### 1. Plugin Structure
```lua
nexus.nvim/
├── lua/
│   └── nexus/
│       ├── init.lua                 -- Main entry point
│       ├── config.lua               -- Configuration management
│       ├── ui/
│       │   ├── renderer.lua        -- Main UI rendering
│       │   ├── components/
│       │   │   ├── header.lua      -- Logo & project name
│       │   │   ├── git_status.lua  -- Git status section
│       │   │   ├── git_commits.lua -- Recent commits
│       │   │   ├── linear.lua      -- Linear integration
│       │   │   ├── quick_links.lua -- File navigation
│       │   │   └── footer.lua      -- Session info
│       │   └── highlights.lua      -- Color definitions
│       ├── integrations/
│       │   ├── linear.lua          -- Linear API client
│       │   ├── github.lua          -- GitHub Issues (future)
│       │   ├── jira.lua           -- Jira (future)
│       │   └── provider.lua        -- Abstract interface
│       ├── git/
│       │   ├── status.lua          -- Git status operations
│       │   ├── commits.lua         -- Commit history
│       │   ├── staging.lua         -- Stage/unstage logic
│       │   └── actions.lua         -- Git command palette
│       ├── cache/
│       │   ├── manager.lua         -- Cache management
│       │   └── storage.lua         -- Local storage
│       ├── actions/
│       │   ├── keymaps.lua         -- Keybinding definitions
│       │   ├── handlers.lua        -- Action handlers
│       │   └── commands.lua        -- Vim commands
│       └── utils/
│           ├── async.lua           -- Async operations
│           ├── icons.lua           -- Icon mappings
│           └── colors.lua          -- Color utilities
├── plugin/
│   └── nexus.lua                   -- Vim plugin entry
└── README.md
```

## Phase 1: Core Functionality (Week 1)

### 1.1 Basic UI Framework
```lua
-- Main render function structure
function M.render()
  -- Create floating window or buffer
  -- Set buffer options (modifiable = false, buftype = nofile)
  -- Apply syntax highlighting
  
  -- Component rendering order:
  -- 1. ASCII Logo
  -- 2. Project name from git
  -- 3. Git status section
  -- 4. Recent commits
  -- 5. Quick navigation links
  -- 6. Footer with session info
end
```

### 1.2 Git Status Implementation
```lua
-- Parse git status --porcelain=v2
-- Support for:
-- • Modified files (M) with +/- line counts
-- • Untracked files (?)
-- • Staged files (A, M in index)
-- • Deleted files (D)
-- • Renamed files (R)
-- • Merge conflicts (U)

-- Visual representation:
-- M  index.html     +25  -3   [staged: partial]
-- ?? config.json              [untracked]
-- D  old_file.js    -150      [deleted]
```

### 1.3 Interactive Git Operations
```lua
-- Keybindings in Nexus buffer:
-- 's' - Stage file/hunk
-- 'u' - Unstage file/hunk
-- 'c' - Quick commit with message prompt
-- 'C' - Commit with editor
-- 'd' - Show diff for file
-- 'x' - Discard changes
-- 'r' - Refresh display
-- '<leader>g' - Open git command palette
```

## Phase 2: Linear Integration (Week 1-2)

### 2.1 Linear API Client
```lua
-- Configuration structure:
config = {
  linear = {
    api_key = "", -- User's Linear API key
    team_id = "", -- Optional: specific team
    show_assigned = true,
    show_created = false,
    max_issues = 5,
    include_backlog = false,
    auto_refresh = 300, -- seconds
  }
}

-- GraphQL queries needed:
-- 1. Fetch assigned issues
-- 2. Fetch current cycle/sprint
-- 3. Update issue status
-- 4. Create new issue
```

### 2.2 Linear Display Component
```lua
-- Display format:
-- Linear Issues (Sprint: 3 days left)
-- ● [IN-PROGRESS] LIN-123: Fix authentication flow (High) [2h]
-- ○ [TODO] LIN-124: Add user preferences endpoint (Med) [4h]
-- ◐ [IN-REVIEW] LIN-125: Update documentation (Low) [1h]
-- ◷ [BLOCKED] LIN-126: Refactor database layer (High)

-- Color coding:
-- High priority: Red
-- Medium: Yellow  
-- Low: Green
-- Blocked: Magenta
-- In Progress: Blue
-- In Review: Cyan
```

### 2.3 Linear Actions
```lua
-- Keybindings in Linear section:
-- 'Enter' - Open issue in browser
-- 'i' - Mark as "In Progress"
-- 'd' - Mark as "Done"
-- 'b' - Create branch from issue (git checkout -b feat/LIN-123-slug)
-- 'c' - Create commit with issue ID
-- 'n' - Create new Linear issue
-- 'r' - Refresh Linear data
-- 'e' - Edit issue title/description
```

## Phase 3: Caching & Performance (Week 2)

### 3.1 Cache Manager
```lua
-- Cache location: ~/.cache/nvim/nexus/
-- Cache structure:
{
  linear = {
    issues = {...},
    last_updated = timestamp,
    ttl = 300
  },
  git = {
    status = {...},
    commits = {...},
    last_updated = timestamp,
    ttl = 30
  }
}

-- Background refresh using vim.loop timer
-- Show stale indicator if cache is old
-- Fallback to cache if API fails
```

### 3.2 Async Operations
```lua
-- Use vim.loop for non-blocking operations
-- Progressive rendering (show what's ready)
-- Loading indicators for slow operations
-- Error handling with graceful degradation
```

## Phase 4: Enhanced Features (Week 2-3)

### 4.1 Smart Git-Linear Integration
```lua
-- Auto-detect Linear issue from branch name
-- Patterns to support:
-- feat/LIN-123-description
-- LIN-123-fix-auth
-- linear-123-feature

-- Auto-generate commit messages:
-- "LIN-123: Fixed authentication flow"

-- Warn if committing without active Linear issue
```

### 4.2 Multi-Provider Architecture
```lua
-- Provider interface:
Provider = {
  name = string,
  fetch_issues = function,
  update_issue = function,
  create_issue = function,
  get_current_sprint = function
}

-- Config for multiple providers:
integrations = {
  linear = { enabled = true, api_key = "..." },
  github = { enabled = false, token = "..." },
  jira = { enabled = false, ... }
}
```

### 4.3 Session History
```lua
-- Track and display:
-- Yesterday: 5 commits on LIN-123 (2.5 hrs)
-- This week: 23 commits, 3 issues completed
-- Current streak: 7 days of commits

-- Store in: ~/.local/share/nvim/nexus/history.json
```

### 4.4 Quick Notes/Memos
```lua
-- 'm' to add memo
-- Memos persist between sessions
-- Display at top of buffer:
-- 📝 "Check with Sarah about API changes before deploying"
-- Support multiple memos with timestamps
```

## Phase 5: Polish & Advanced Features (Week 3-4)

### 5.1 PR/MR Status Integration
```lua
-- Show pull request status:
-- Pull Requests:
-- ✓ #234 Ready to merge (2 approvals)
-- ⚠ #235 Changes requested by @john
-- ○ #236 Draft PR
```

### 5.2 Team Awareness
```lua
-- If Linear API provides team activity:
-- Team Activity:
-- • John is reviewing your PR #234
-- • Sarah completed LIN-789
-- • Mike started LIN-790
```

### 5.3 Time-Based Intelligence
```lua
-- Smart suggestions based on time:
-- Morning: Show high-priority issues
-- End of day: Suggest committing WIP
-- Friday: Show weekly summary
-- Sprint end: Highlight incomplete issues
```

### 5.4 Customizable Sections
```lua
-- Allow users to show/hide sections:
config = {
  sections = {
    logo = true,
    git_status = true,
    git_commits = true,
    linear = true,
    quick_links = true,
    history = false,
    team_activity = false
  },
  layout = "vertical" -- or "horizontal" for wide screens
}
```

## Configuration Example
```lua
require('nexus').setup({
  -- UI Settings
  ui = {
    logo = "ascii", -- "ascii" | "image" | "none"
    width = 80,
    height = 35,
    position = "center",
  },
  
  -- Git Settings
  git = {
    show_commits = 5,
    show_staged_separately = true,
    auto_stage_tracked = false,
  },
  
  -- Integration Settings
  integrations = {
    linear = {
      enabled = true,
      api_key = vim.env.LINEAR_API_KEY,
      show_assigned = true,
      max_issues = 5,
      auto_refresh = 300,
    },
  },
  
  -- Keymaps (can be customized)
  keymaps = {
    stage = 's',
    unstage = 'u',
    commit = 'c',
    diff = 'd',
    refresh = 'r',
    quit = 'q',
    git_menu = '<leader>g',
  },
  
  -- Cache Settings
  cache = {
    enabled = true,
    ttl = {
      git = 30,
      linear = 300,
    },
  },
})
```

## Image.nvim Integration
```lua
-- For logo display using image.nvim:
-- 1. Detect if image.nvim is available
-- 2. Load logo from: ~/.config/nvim/nexus/logo.png
-- 3. Fall back to ASCII if not available
-- 4. Support custom logo paths in config
```

## Testing Plan
1. **Unit tests** for git parsing functions
2. **Mock Linear API** responses for testing
3. **Test with various git states** (clean, dirty, merge conflicts)
4. **Performance testing** with large repos
5. **Multi-platform testing** (Linux, macOS, WSL)

## Documentation Requirements
1. **README** with GIF demos
2. **Wiki** with detailed configuration
3. **Video tutorial** showing Linear integration
4. **Troubleshooting guide** for common issues
5. **API documentation** for extensions

## Success Metrics
- Startup time < 50ms with cache
- Support for repos with 1000+ files
- Linear API calls < 2 per session (use cache)
- Memory usage < 10MB
- Works with Neovim 0.8+

## Marketing Hooks
1. "The only Neovim dashboard that knows what you're supposed to be working on"
2. "Stop context switching - see Linear issues right in Neovim"
3. "Git + Linear + Navigation = Developer Flow State"
4. "Built for engineers who ship fast but stay organized"

## Future Expansion Ideas
- Slack integration for team messages
- Calendar integration for meetings
- CI/CD pipeline status
- Database migration status
- Docker container health
- Kubernetes pod status
- Time tracking integration
- Pomodoro timer with issue association
