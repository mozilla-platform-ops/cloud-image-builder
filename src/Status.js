import React from 'react'
import Task from './Task';
import Tasks from './Tasks';

class Status extends React.Component {
  state = {
    showAllTasks: false,
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
          }
        })
        .catch(console.log);
        break;
    }
  }

  render() {
    return (
      <li style={{
        color: (this.props.status.state === 'success')
          ? 'green'
          : (this.props.status.state === 'failure')
            ? 'red'
            : 'gray'
      }}>
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
        ({this.state.taskCount} tasks in group <a href={this.props.status.target_url} title={this.state.taskGroupId}>{this.state.taskGroupId && this.state.taskGroupId.substring(0, 7)}...</a>
        &nbsp;
        [
          {
            ['completed', 'failed', 'exception', 'running', 'pending', 'unscheduled'].map(status => (
              (this.state.tasks.filter(t => t.status.state === status).length)
                ? (
                  <span style={{
                    color: (status === 'completed')
                      ? 'green'
                      : (status === 'failed')
                        ? 'red'
                        : (status === 'exception')
                          ? 'orange'
                          : (status === 'pending')
                            ? 'darkorchid'
                            : (status === 'running')
                              ? 'steelblue'
                              : (status === 'unscheduled')
                                ? 'gray'
                                : 'black' }}>
                    &nbsp;{status}: {this.state.tasks.filter(t => t.status.state === status).length}&nbsp;
                  </span>
                )
                : ''
            ))
          }
          {
            [0, 1].map(result => (
              (this.state.builds.filter(b => b.result === result).length)
                ? (
                  <span style={{
                    color: (result === 0)
                      ? 'green'
                      : (result === 1)
                        ? 'red'
                        : 'black' }}>
                    &nbsp;{this.travisBuildResults[result]}: {this.state.builds.filter(b => b.result === result).length}&nbsp;
                  </span>
                )
                : ''
            ))
          }
        ]
        )
        {
          (this.state.showAllTasks)
            ? <Tasks tasks={this.state.tasks} rootUrl={'https://' + (new URL(this.props.status.target_url)).hostname} />
            : (
                <ul>
                  {
                    (this.state.tasks.filter(t => t.task.metadata.name.startsWith('04 :: generate') && t.status.state === 'completed').map(task => (
                      <Task task={task} rootUrl={'https://' + (new URL(this.props.status.target_url)).hostname} />
                    )))
                  }
                </ul>
              )
        }
      </li>
    );
  }
}

export default Status;
