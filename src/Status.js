import React from 'react'
import Task from './Task';
import Tasks from './Tasks';

class Status extends React.Component {
  state = {
    showAllTasks: false,
    taskGroupId: null,
    taskCount: 0,
    tasks: []
  };

  componentDidMount() {
    let tasksApi = false;
    switch (this.props.status.context) {
      case 'continuous-integration/travis-ci/push':
        tasksApi = false;
        break;
      default:
        let taskGroupHtmlUrl = new URL(this.props.status.target_url);
        let taskGroupId = this.props.status.target_url.substring(this.props.status.target_url.lastIndexOf('/') + 1);
        this.setState(state => ({
          taskGroupId: taskGroupId
        }));
        tasksApi = 'https://' + taskGroupHtmlUrl.hostname + '/api/queue/v1/task-group/' + taskGroupId + '/list';
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
    if (tasksApi) {
      fetch(tasksApi)
      .then(responseTasksApi => responseTasksApi.json())
      .then((container) => {
        if (container.tasks && container.tasks.length) {
          this.setState(state => ({
            tasks: container.tasks
          }));
        } else {
          console.log('error fetching: ' + tasksApi);
          console.log(container);
        }
      })
      .catch(console.log);
    }
  }

  render() {
    return (
      <li style={{
        color: (this.props.status.state === 'success')
          ? 'green'
          : (this.props.status.state === 'failure')
            ? 'red'
            : 'black'
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
        ({this.state.taskCount} tasks in group <a href={this.props.status.target_url}>{this.state.taskGroupId})</a>
        {
          (this.state.showAllTasks)
            ? <Tasks tasks={this.state.tasks} />
            : (this.state.tasks.some(t => t.task.metadata.name.startsWith('04 :: generate')))
              ? (
                <ul>
                  <Task task={this.state.tasks.find(t => t.task.metadata.name.startsWith('04 :: generate'))} />
                </ul>
              )
              : ''
        }
      </li>
    );
  }
}

export default Status;
