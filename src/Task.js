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
              : (this.props.task.status.state === 'pending')
                ? 'darkorchid'
                : (this.props.task.status.state === 'running')
                  ? 'steelblue'
                  : (this.props.task.status.state === 'unscheduled')
                    ? 'gray'
                    : 'black' }}>
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
