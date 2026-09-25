// Pause the subtle loop offscreen and in background tabs. CSS handles reduced motion.
const scene=document.querySelector('.product-scene');
if(scene&&'IntersectionObserver' in window){
  let visible=false;
  const update=()=>{scene.dataset.moving=String(visible&&!document.hidden);};
  const observer=new IntersectionObserver(entries=>{
    visible=entries.some(entry=>entry.isIntersecting);
    update();
  },{threshold:0});
  observer.observe(scene);
  document.addEventListener('visibilitychange',update);
}
