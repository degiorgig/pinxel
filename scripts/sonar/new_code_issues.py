#!/usr/bin/env python3
"""Prints the open issues and security hotspots on new code of a SonarQube Cloud analysis.
new_code_issues.py <projectKey> [<pullRequest>]
The token comes from SONAR_TOKEN. Without a pull request it reads the main branch."""
import json
import os
import sys
import urllib.parse
import urllib.request

HOST = "https://sonarcloud.io"


def get(path, **params):
    request = urllib.request.Request(f"{HOST}{path}?{urllib.parse.urlencode(params)}",
                                     headers={"Authorization": f"Bearer {os.environ['SONAR_TOKEN']}"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def location(item):
    return f"{item['component'].split(':', 1)[-1]}:{item.get('line', '-')}"


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    project = sys.argv[1]
    scope = {"pullRequest": sys.argv[2]} if len(sys.argv) == 3 and sys.argv[2] else {}

    issues = get("/api/issues/search", componentKeys=project, issueStatuses="OPEN,CONFIRMED",
                 inNewCodePeriod="true", ps=100, **scope)
    print(f"Issues on new code: {issues['total']}")
    for issue in issues["issues"]:
        impacts = ",".join(f"{i['softwareQuality']}/{i['severity']}" for i in issue.get("impacts", []))
        print(f"  {impacts or issue.get('severity')}  {issue['rule']}  {location(issue)}  {issue['message']}")

    hotspots = get("/api/hotspots/search", projectKey=project, status="TO_REVIEW", inNewCodePeriod="true",
                   ps=100, **scope)
    print(f"Security hotspots to review: {hotspots['paging']['total']}")
    for hotspot in hotspots["hotspots"]:
        print(f"  {hotspot['vulnerabilityProbability']}  {hotspot['ruleKey']}  {location(hotspot)}  {hotspot['message']}")


if __name__ == "__main__":
    main()
