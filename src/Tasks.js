import React from 'react';
import Tab from 'react-bootstrap/Tab';
import Tabs from 'react-bootstrap/Tabs';
import Task from './Task';

class Tasks extends React.Component {
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
    }
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

  render() {
    switch (this.props.tasks[0].task.metadata.name.slice(0, 2)) {
      case '01': {
        let platforms = [...new Set(this.props.tasks.map(t => t.task.metadata.name.split(' ')[3]))].sort().reverse();
        if (platforms.length > 1) {
          return (
            <Tabs defaultActiveKey={platforms[0]}>
              {
                platforms.map(platform => (
                  <Tab
                    key={platform}
                    eventKey={platform}
                    title={
                      <span>
                        {platform}
                      </span>
                    }>
                    <ul style={{listStyleType: 'none', margin: 0, padding: 0}}>
                      {
                        this.props.tasks.filter(t => t.task.metadata.name.includes(platform)).sort((a, b) => ((a.task.metadata.name < b.task.metadata.name) ? -1 : (a.task.metadata.name > b.task.metadata.name) ? 1 : 0)).map(task => (
                          <Task task={task} key={task.status.taskId} rootUrl={this.props.rootUrl} appender={this.appendToSummary} />
                        ))
                      }
                    </ul>
                  </Tab>
                ))
              }
            </Tabs>
          );
        }
        return (
          <ul>
            {
              this.props.tasks.sort((a, b) => ((a.task.metadata.name < b.task.metadata.name) ? -1 : (a.task.metadata.name > b.task.metadata.name) ? 1 : 0)).map(task => (
                <Task task={task} key={task.status.taskId} rootUrl={this.props.rootUrl} appender={this.appendToSummary} />
              ))
            }
          </ul>
        );
      }
      case '02': {
        let platformRegions = [...new Set(this.props.tasks.map(t => t.task.metadata.name.split(' ')[3] + '/' + t.task.metadata.name.split(' ').pop()))].sort();
        if (platformRegions.length > 1) {
          return (
            <Tabs defaultActiveKey={platformRegions[0]}>
              {
                platformRegions.map(platformRegion => (
                  <Tab
                    key={platformRegion}
                    eventKey={platformRegion}
                    title={
                      <span>
                        {platformRegion}
                      </span>
                    }>
                    <ul style={{listStyleType: 'none', margin: 0, padding: 0}}>
                      {
                        this.props.tasks.filter(t => t.task.metadata.name.includes(platformRegion.split('/')[0]) && t.task.metadata.name.endsWith(platformRegion.split('/').pop())).sort((a, b) => ((a.task.metadata.name < b.task.metadata.name) ? -1 : (a.task.metadata.name > b.task.metadata.name) ? 1 : 0)).map(task => (
                          <Task task={task} key={task.status.taskId} rootUrl={this.props.rootUrl} appender={this.appendToSummary} />
                        ))
                      }
                    </ul>
                  </Tab>
                ))
              }
            </Tabs>
          );
        }
        return (
          <ul>
            {
              this.props.tasks.sort((a, b) => ((a.task.metadata.name < b.task.metadata.name) ? -1 : (a.task.metadata.name > b.task.metadata.name) ? 1 : 0)).map(task => (
                <Task task={task} key={task.status.taskId} rootUrl={this.props.rootUrl} appender={this.appendToSummary} />
              ))
            }
          </ul>
        );
      }
      default: {
        return (
          <ul>
            {
              this.props.tasks.sort((a, b) => ((a.task.metadata.name < b.task.metadata.name) ? -1 : (a.task.metadata.name > b.task.metadata.name) ? 1 : 0)).map(task => (
                <Task task={task} key={task.status.taskId} rootUrl={this.props.rootUrl} appender={this.appendToSummary} />
              ))
            }
          </ul>
        );
      }
    }
  }
}

export default Tasks;
