import React from 'react'
import Runs from './Runs';

class Task extends React.Component {
  render() {
    return (
      <li>
        {this.props.task.task.metadata.name}
        &nbsp;
        <a href={this.props.rootUrl + '/tasks/' + this.props.task.status.taskId} title={this.props.task.status.taskId}>
          {this.props.task.status.taskId.substring(0, 7)}...
        </a>
        <Runs runs={this.props.task.status.runs} taskId={this.props.task.status.taskId} rootUrl={this.props.rootUrl} />
      </li>
    );
  }
}

export default Task;
