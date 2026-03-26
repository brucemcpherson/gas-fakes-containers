
# Project: Gas Fakes
# Gemini CLI Configuration

## Model Settings
- **Default Model**: gemini 3 auto
- **Thinking Level**: minimal
- **Response Mode**: direct

## Tool Restrictions
- **Disable Tools**: none
- **Grounding**: none

# Instructions
You are an expert developer. For this project, prioritize speed and low-token usage. 
Do not attempt to search the web or run complex reasoning chains unless explicitly asked.
You should always read the .agent/workflows file for how to do things.
You are allowed to access any file in the repo, even if it excluded by .gitignore. However **/node_modules should normally be excluded except when explicitly asked.##

## Objectives

Here we will be handling building and deploying gas-fakes on multiple cloud platforms, with particular attention to automating authentication and build/deploy pipelines.  We will be using cloud build to build and push images to artifact registry, and then deploy to the various cloud platforms.  Usually we will be using Workload Identity Federation to authenticate to the various cloud platforms, along with dwd.

## Related
This is a companion repo to [gas-fakes](https://github.com/brucemcpherson/gas-fakes).  You can refer to the latest development version here ../gas-fakes. We will often need to reference that for how things work. in particular, see ../gas-fakes/.agent for gas-fakes gemini specific instructions.


