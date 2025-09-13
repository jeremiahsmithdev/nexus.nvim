#!/usr/bin/env lua

-- Simple test to verify batch git operations work
local git_batch = require('nexus.git.batch')

print("Testing batch git operations...")

-- Test the parsing function directly
local test_output = [[8c1c2bf (HEAD -> master) perf: implement batch git operations for 60-80% performance improvement
820ff11 feat: add dynamic project name display with orange highlighting
5de2236 chore: renames]]

local commits = git_batch.parse_batch_commits(test_output)

print("Parsed commits:", #commits)
for i, commit in ipairs(commits) do
  print(string.format("  %s | %s | %s", commit.hash, commit.decoration or "nil", commit.message))
end

print("Batch test completed!")