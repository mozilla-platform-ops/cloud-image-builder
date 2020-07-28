import React from 'react'
import Tasks from './Tasks';
import StatusBadgeVariantMap from './StatusBadgeVariantMap';
import Badge from 'react-bootstrap/Badge';

class Status extends React.Component {
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
    taskGroupId: null,
    taskCount: 0,
    tasks: [],
    builds: [],
    travisApiResponse: {}
  };
  travisBuildResults = [
    'completed',
    'failed',
  ];

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
    switch (this.props.status.context) {
      case 'continuous-integration/travis-ci/push':
        let pathname = (new URL(this.props.status.target_url)).pathname;
        let buildId = pathname.substring(pathname.lastIndexOf('/') + 1);
        this.setState(state => ({
          taskGroupId: buildId
        }));
        let buildsApi = 'https://api.travis-ci.org/repos/mozilla-platform-ops/cloud-image-builder/builds/' + buildId;
        fetch(buildsApi)
        .then(responseBuildsApi => responseBuildsApi.json())
        .then((container) => {
          if (container.matrix) {
            this.setState(state => ({
              taskCount: container.matrix.length,
              builds: container.matrix,
              travisApiResponse: container
            }));
            this.appendToSummary({
              task: {
                completed: { ...container.matrix.filter(x => x.result === 0).map(x => [x.id, x.finished_at]).reduce((o, [k, v]) => ({...o, [k]: v}), {}) },
                failed: { ...container.matrix.filter(x => x.result !== null && x.result !== 0).map(x => [x.id, x.finished_at]).reduce((o, [k, v]) => ({...o, [k]: v}), {}) },
                exception: {},
                running: {},
                pending: { ...container.matrix.filter(x => x.result === null).map(x => [x.id, x.finished_at]).reduce((o, [k, v]) => ({...o, [k]: v}), {}) },
                unscheduled: {}
              },
              image: []
            });
          }
        })
        .catch(console.log);
        break;
      default:
        let taskGroupHtmlUrl = new URL(this.props.status.target_url);
        let taskGroupId = this.props.status.target_url.substring(this.props.status.target_url.lastIndexOf('/') + 1);
        this.setState(state => ({
          taskGroupId: taskGroupId
        }));
        let tasksApi = 'https://' + taskGroupHtmlUrl.hostname + '/api/queue/v1/task-group/' + taskGroupId + '/list';
        fetch(tasksApi)
        .then(responseTasksApi => responseTasksApi.json())
        .then((container) => {
          if (container.tasks && container.tasks.length) {
            this.setState(state => ({
              taskCount: container.tasks.length,
              tasks: container.tasks//.sort((a, b) => a.task.metadata.name.localeCompare(b.task.metadata.name))
            }));
            this.appendToSummary({
              task: {
                completed: { ...container.tasks.filter(x => x.status.state === 'completed').map(x => [x.status.taskId, x.status.runs[x.status.runs.length - 1].resolved]).reduce((o, [k, v]) => ({...o, [k]: v}), {}) },
                failed: { ...container.tasks.filter(x => x.status.state === 'failed').map(x => [x.status.taskId, x.status.runs[x.status.runs.length - 1].resolved]).reduce((o, [k, v]) => ({...o, [k]: v}), {}) },
                exception: { ...container.tasks.filter(x => x.status.state === 'exception').map(x => [x.status.taskId, x.status.runs[x.status.runs.length - 1].resolved]).reduce((o, [k, v]) => ({...o, [k]: v}), {}) },
                running: { ...container.tasks.filter(x => x.status.state === 'running').map(x => [x.status.taskId, null]).reduce((o, [k, v]) => ({...o, [k]: v}), {}) },
                pending: { ...container.tasks.filter(x => x.status.state === 'pending').map(x => [x.status.taskId, null]).reduce((o, [k, v]) => ({...o, [k]: v}), {}) },
                unscheduled: { ...container.tasks.filter(x => x.status.state === 'unscheduled').map(x => [x.status.taskId, null]).reduce((o, [k, v]) => ({...o, [k]: v}), {}) },
              },
              image: []
            });
          }
        })
        .catch(console.log);
        break;
    }
  }

  render() {
    return (
      <li>
        {
          new Intl.DateTimeFormat('en-GB', {
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: 'numeric',
            minute: 'numeric',
            timeZoneName: 'short'
          }).format(new Date(this.props.status.updated_at))
        }
        &nbsp;
        {this.props.status.description.toLowerCase()}
        &nbsp;
        (
          {this.state.taskCount} tasks in group
          &nbsp;
          <a href={this.props.status.target_url} title={this.state.taskGroupId}>
            {
              (this.state.builds.length)
                ? this.state.taskGroupId
                : (this.state.taskGroupId && this.state.taskGroupId.slice(0, 7)) + '...'
            }
          </a>
          &nbsp;
          {
            Object.keys(StatusBadgeVariantMap).map(status => (
              (this.state.tasks.filter(t => t.status.state === status).length)
                ? (
                    <Badge
                      key={status}
                      style={{ margin: '0 1px' }}
                      variant={StatusBadgeVariantMap[status]}
                      title={status + ': ' + this.state.tasks.filter(t => t.status.state === status).length}>
                      {this.state.tasks.filter(t => t.status.state === status).length}
                    </Badge>
                  )
                : ''
            ))
          }
          {
            [0, 1, null].map((result, rI) => (
              (this.state.builds.filter(b => b.result === result).length)
                ? (
                    <Badge
                      key={rI}
                      style={{ margin: '0 1px' }}
                      variant={(result === null) ? 'info' : StatusBadgeVariantMap[this.travisBuildResults[result]]}
                      title={this.travisBuildResults[result] + ': ' + this.state.builds.filter(b => b.result === result).length}>
                      {this.state.builds.filter(b => b.result === result).length}
                    </Badge>
                  )
                : ''
            ))
          }
        )
        {
          <Tasks tasks={this.state.tasks} rootUrl={'https://' + (new URL(this.props.status.target_url)).hostname} appender={this.appendToSummary} settings={this.props.settings} />
        }
      </li>
    );
  }
}

export default Status;
