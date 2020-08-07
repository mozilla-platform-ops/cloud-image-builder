import React from 'react';
import ImageGallery from 'react-image-gallery';
//import Screenshot from './Screenshot';

class Screenshots extends React.Component {
  state = {
    screenshots: [],
    thumbnailPosition: (window.innerWidth < 960) ? 'bottom' : 'left',
    galleryWidth: (window.innerWidth < 960) ? 640 : (640 + 48 + 10)
  };

  componentDidMount() {
    window.addEventListener('resize', this.updateDimensions);
    this.setState(state => ({
      screenshots: this.props.screenshots.map(screenshot => {
        let alt = (screenshot.name.split('/').pop().replace(/\.[^/.]+$/, '').split('').reverse().join('').replace('-', ' ').split('').reverse().join(''));
        let dt = alt.split(' ')[1];
        let title = alt.split(' ')[0] + ' - ' + (
          new Intl.DateTimeFormat('en-GB', {
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: 'numeric',
            minute: 'numeric',
            timeZoneName: 'short'
          }).format(new Date(dt.slice(0, 4) + '-' + dt.slice(4, 6) + '-' + dt.slice(6, 8) + 'T' + dt.slice(9, 11) + ':' + dt.slice(11, 13) + ':00Z')));
        return {
          original: ('https://artifacts.tcstage.mozaws.net/' + this.props.taskId + '/' + this.props.runId + '/' + screenshot.name),
          originalAlt: alt,
          originalTitle: title,
          thumbnail: ('https://artifacts.tcstage.mozaws.net/' + this.props.taskId + '/' + this.props.runId + '/' + screenshot.name.replace('/full/', '/thumbnail/').replace('.png', '-64x48.png')),
          thumbnailAlt: alt,
          thumbnailTitle: title
        };
      })
    }));
  }

  updateDimensions = () => {
    if (window.innerWidth < 960) {
      this.setState(state => ({
        thumbnailPosition: 'bottom',
        galleryWidth: 640
      }));
    } else {
      this.setState(state => ({
        thumbnailPosition: 'left',
        galleryWidth: (640 + 48 + 10)
      }));
    }
  };

  componentWillUnmount() {
    window.removeEventListener('resize', this.updateDimensions);
  }

  render() {
    return (
      <div style={{width: '' + this.state.galleryWidth + 'px'}}>
        <ImageGallery items={this.state.screenshots} startIndex={(this.state.screenshots.length - 1)} showIndex={true} thumbnailPosition={this.state.thumbnailPosition} />
      </div>
    );
  }
}

export default Screenshots;