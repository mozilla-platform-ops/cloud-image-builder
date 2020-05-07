import React from 'react'

class Run extends React.Component {
  state = {
    artifacts: [],
    images: []
  };

  componentDidMount() {
    fetch(this.props.rootUrl + '/api/queue/v1/task/' + this.props.taskId + '/runs/' + this.props.run.runId + '/artifacts')
    .then(responseArtifactsApi => responseArtifactsApi.json())
    .then((container) => {
      if (container.artifacts && container.artifacts.length) {
        this.setState(state => ({
          artifacts: container.artifacts
        }));
        if (container.artifacts.some(a => a.name.startsWith('public/') && a.name.endsWith('.json'))) {
          let artifact = container.artifacts.find(a => a.name.startsWith('public/') && a.name.endsWith('.json'))
          fetch(this.props.rootUrl + '/api/queue/v1/task/' + this.props.taskId + '/runs/' + this.props.run.runId + '/artifacts/' + artifact.name)
          .then(responseArtifactApi => responseArtifactApi.json())
          .then((container) => {
            if (container.launchConfigs && container.launchConfigs.length) {
              this.setState(state => ({
                images: container.launchConfigs.map(launchConfig => launchConfig.storageProfile.imageReference.id)
              }));
            } else {
              console.log(container);
            }
          })
          .catch(console.log);
        }
      } else {
        console.log(container);
      }
    })
    .catch(console.log);
  }

  render() {
    return (
      <li style={{
        color: (this.props.run.state === 'completed')
          ? 'green'
          : (this.props.run.state === 'failed')
            ? 'red'
            : (this.props.run.state === 'exception')
              ? 'orange'
              : (this.props.run.state === 'pending')
                ? 'darkorchid'
                : (this.props.run.state === 'running')
                  ? 'steelblue'
                  : (this.props.run.state === 'unscheduled')
                    ? 'gray'
                    : 'black' }}>
        <a href={this.props.rootUrl + '/tasks/' + this.props.taskId}>
         run {this.props.run.runId}
        </a> {this.props.run.state}
          {
            (this.props.run.state === 'completed')
              ? (
                <ul style={{ color: 'black' }}>
                  {
                    this.state.images.map(image => (
                      <li key={image}>
                        {image.substring(image.lastIndexOf('/') + 1)}
                      </li>
                    ))
                  }
                </ul>
              )
              : ''
          }
      </li>
    );
  }
}

export default Run;
