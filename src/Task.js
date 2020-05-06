import React from 'react'
import Runs from './Runs';

class Task extends React.Component {
  render() {
    return (
      <li style={{
        color: (this.props.task.status.state === 'completed')
          ? 'green'
          : (this.props.task.status.state === 'failed')
            ? 'red'
            : (this.props.task.status.state === 'exception')
              ? 'orange'
              : 'gray'
      }}>
        {this.props.task.task.metadata.name}
        <Runs runs={this.props.task.status.runs} taskId={this.props.task.status.taskId} rootUrl={this.props.rootUrl} />
      </li>
    );
  }
}

export default Task;
