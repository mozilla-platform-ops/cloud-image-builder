import React from 'react';

class InstanceLogs extends React.Component {
  state = {
    logs: []
  };

  componentDidMount() {
    this.setState(state => ({
      logs: this.props.logs.map(log => ({
        name: log.name,
        contentType: log.contentType,
        url: ('https://artifacts.tcstage.mozaws.net/' + this.props.taskId + '/' + this.props.runId + '/' + log.name)
      }))
    }));
  }

  render() {
    return (
      <ul>
        {
          this.state.logs.map(log => (
            <li key={log.name}>
              <a href={log.url} target="_blank" rel="noopener noreferrer">
                {log.name}
              </a>
            </li>
          ))
        }
      </ul>
    );
  }
}

export default InstanceLogs;