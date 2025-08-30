#!/bin/bash

# Script to display disk quota usage for a specified GCP project.
# It attempts to categorize usage into infrastructure and application related.

# Function to display usage
display_usage() {
    echo "Usage: $0 <project_id>"
    echo "Example: $0 my-gcp-project-123"
}

# Check if project_id is provided
if [ -z "$1" ]; then
    echo "Error: Project ID not provided."
    display_usage
    exit 1
fi

PROJECT_ID="$1"

echo "Fetching disk quota usage for project: $PROJECT_ID"
echo "--------------------------------------------------"

# Get project-wide quota information
echo "Project Quota Information:"
gcloud compute project-info describe --project="$PROJECT_ID" | grep -E "QUOTA|METRIC|LIMIT|USAGE"
echo ""

# List all persistent disks in the project
echo "Persistent Disk Usage (Infrastructure & Application):"
echo "Note: Categorization into 'infrastructure' and 'application' is an approximation."
echo "      You may need to refine this based on your specific resource tagging/naming conventions."
echo ""

# Get disk list and format output
gcloud compute disks list --project="$PROJECT_ID" --format="table(name,zone,sizeGb,type,users.map().list():label=ATTACHED_TO)"

echo ""
echo "Disk usage details above include both infrastructure and application related disks."
echo "To further differentiate, consider using resource labels or naming conventions in your GCP project."
