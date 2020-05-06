import React from 'react'
import Task from './Task';

class Tasks extends React.Component {
  render() {
    return (
      <ul>
        {
          this.props.tasks.map(task => (
            <Task task={task} key={task.status.taskId} rootUrl={this.props.rootUrl} />
          ))
        }
      </ul>
    );
  }
}

export default Tasks;
