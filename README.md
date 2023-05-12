# agent-docker

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.1.33](https://img.shields.io/badge/AppVersion-0.1.33-informational?style=flat-square)

Scalr agent for a self-hosted pool

**Homepage:** <https://github.com/Scalr/agent-helm/>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| scalr | <packages@scalr.com> |  |

## Values

<table>
	<thead>
		<th>Key</th>
		<th>Type</th>
		<th>Default</th>
		<th>Description</th>
	</thead>
	<tbody>
		<tr>
			<td>affinity</td>
			<td>object</td>
			<td><pre lang="json">
{}
</pre>
</td>
			<td>Affinity rules to control how the Scalr Agent pods are scheduled on nodes</td>
		</tr>
		<tr>
			<td>agent.image</td>
			<td>object</td>
			<td><pre lang="json">
{
  "pullPolicy": "IfNotPresent",
  "repository": "scalr/agent",
  "tag": "0.1.30"
}
</pre>
</td>
			<td>Docker image configuration for Scalr Agent</td>
		</tr>
		<tr>
			<td>agent.token</td>
			<td>string</td>
			<td><pre lang="json">
null
</pre>
</td>
			<td>A value for agent.token must be provided for Scalr Agent authentication</td>
		</tr>
		<tr>
			<td>agent.url</td>
			<td>string</td>
			<td><pre lang="json">
null
</pre>
</td>
			<td>A value for agent.url must be provided to specify the Scalr API endpoint</td>
		</tr>
		<tr>
			<td>docker</td>
			<td>object</td>
			<td><pre lang="json">
{
  "image": {
    "pullPolicy": "IfNotPresent",
    "repository": "docker",
    "tag": "20.10.23-dind"
  }
}
</pre>
</td>
			<td>Docker configuration for running Docker-in-Docker containers</td>
		</tr>
		<tr>
			<td>fullnameOverride</td>
			<td>string</td>
			<td><pre lang="json">
""
</pre>
</td>
			<td>String to fully override the name used in resources</td>
		</tr>
		<tr>
			<td>imagePullSecrets</td>
			<td>list</td>
			<td><pre lang="json">
[]
</pre>
</td>
			<td>List of secrets for pulling images from private registries</td>
		</tr>
		<tr>
			<td>nameOverride</td>
			<td>string</td>
			<td><pre lang="json">
""
</pre>
</td>
			<td>String to partially override the name used in resources</td>
		</tr>
		<tr>
			<td>nodeSelector</td>
			<td>object</td>
			<td><pre lang="json">
{}
</pre>
</td>
			<td>NodeSelector for specifying which nodes the Scalr Agent pods should be deployed on</td>
		</tr>
		<tr>
			<td>podAnnotations</td>
			<td>object</td>
			<td><pre lang="json">
{}
</pre>
</td>
			<td>Additional annotations to be added to the Scalr Agent pods</td>
		</tr>
		<tr>
			<td>podSecurityContext</td>
			<td>object</td>
			<td><pre lang="json">
{}
</pre>
</td>
			<td>Pod security context for the Scalr Agent deployment</td>
		</tr>
		<tr>
			<td>replicaCount</td>
			<td>int</td>
			<td><pre lang="json">
1
</pre>
</td>
			<td>Number of replicas for the Scalr Agent deployment</td>
		</tr>
		<tr>
			<td>resources</td>
			<td>object</td>
			<td><pre lang="json">
{
  "limits": {
    "memory": "2048Mi"
  },
  "requests": {
    "cpu": "500m",
    "memory": "2048Mi"
  }
}
</pre>
</td>
			<td>Resource limits and requests for the Scalr Agent containers</td>
		</tr>
		<tr>
			<td>securityContext</td>
			<td>object</td>
			<td><pre lang="json">
{
  "privileged": true,
  "procMount": "Default"
}
</pre>
</td>
			<td>Security context for the Scalr Agent containers</td>
		</tr>
		<tr>
			<td>serviceAccount</td>
			<td>object</td>
			<td><pre lang="json">
{
  "annotations": {},
  "create": true,
  "name": ""
}
</pre>
</td>
			<td>ServiceAccount configuration for Scalr Agent</td>
		</tr>
		<tr>
			<td>tolerations</td>
			<td>list</td>
			<td><pre lang="json">
[]
</pre>
</td>
			<td>Tolerations for the Scalr Agent pods, allowing them to run on tainted nodes</td>
		</tr>
	</tbody>
</table>

