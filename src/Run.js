import React from 'react'
import Badge from 'react-bootstrap/Badge';
import Button from 'react-bootstrap/Button';
import StatusBadgeVariantMap from './StatusBadgeVariantMap';
//import { Server } from 'react-bootstrap-icons';

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
      <li>
        <Button
          size="sm"
          href={this.props.rootUrl + '/tasks/' + this.props.taskId + '/runs/' + this.props.run.runId}
          style={{ marginLeft: '0.7em' }}
          variant={'outline-' + StatusBadgeVariantMap[this.props.run.state]}
          title={'task ' + this.props.taskId + ', run ' + this.props.run.runId + ': ' + this.props.run.state}>
          {'task ' + this.props.taskId + ', run ' + this.props.run.runId}
        </Button>
        {
          (this.props.run.state === 'completed' && this.state.images.length)
            ? (
              <div>
                <span>worker manager image deployments:</span>
                <ul>
                  {
                    this.state.images.map(image => (
                      <li key={image}>
                        {image.substring(image.lastIndexOf('/') + 1)}
                      </li>
                    ))
                  }
                </ul>
              </div>
            )
            : ''
        }
      </li>
    );
  }
}

export default Run;
