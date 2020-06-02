import React from 'react'
//import Badge from 'react-bootstrap/Badge';
import Button from 'react-bootstrap/Button';
import Images from './Images';
import StatusBadgeVariantMap from './StatusBadgeVariantMap';
//import { Server } from 'react-bootstrap-icons';

class Run extends React.Component {
  state = {
    summary: {
      task: {
        completed: {},
        failed: {},
        exception: {},
        running: {},
        pending: {},
        unscheduled: {}
      },
      image: {}
    },
    artifacts: [],
    images: []
  };

  constructor(props) {
    super(props);
    this.appendToSummary = this.appendToSummary.bind(this);
  }

  appendToSummary(summary) {
    this.setState(state => {
      let combined = {
        task: {
          completed: { ...state.summary.task.completed, ...summary.task.completed },
          failed: { ...state.summary.task.failed, ...summary.task.failed },
          exception: { ...state.summary.task.exception, ...summary.task.exception },
          running: { ...state.summary.task.running, ...summary.task.running },
          pending: { ...state.summary.task.pending, ...summary.task.pending },
          unscheduled: { ...state.summary.task.unscheduled, ...summary.task.unscheduled }
        },
        image: { ...state.summary.image, ...summary.image }
      };
      this.props.appender(combined);
      return { summary: combined };
    });
  }

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
              let imageIds = container.launchConfigs.map(launchConfig => launchConfig.storageProfile.imageReference.id);
              this.setState(state => ({
                images: imageIds
              }));
              let re = /^((north|south|east|west|(north-|south-|east-|west-)?central)-us(-2)?)-(.*)-(win.*)-([a-f0-9]{7})-([a-f0-9]{7})$/i;
              this.appendToSummary({
                task: {
                  completed: 0,
                  failed: 0,
                  exception: 0,
                  running: 0,
                  pending: 0,
                  unscheduled: 0
                },
                image: imageIds.reduce(function(a, imageId, i) {
                  let image = imageId.substring(imageId.lastIndexOf('/') + 1);
                  let matches = image.match(re);
                  let pool = matches[5] + '/' + matches[6];
                  a[pool] = (a[pool] || 0) + 1;
                  return a;
                }, {})
              });
            } else {
              //console.log(container);
            }
          })
          .catch(console.log);
        }
      } else {
        //console.log(container);
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
            ? (<Images images={this.state.images} /> )
            : ''
        }
      </li>
    );
  }
}

export default Run;
