# Guia de Revisão de Código Angular

> Guia de revisão de código Angular 17+, cobrindo Signals, componentes Standalone, anti-padrões de RxJS, detecção de mudanças Zoneless, boas práticas de template e otimização de performance como temas centrais.

## Índice

- [Signals e Detecção de Mudanças](#signals-e-detecção-de-mudanças)
- [Migração para Componentes Standalone](#migração-para-componentes-standalone)
- [Anti-padrões de RxJS](#anti-padrões-de-rxjs)
- [Detecção de Mudanças Zoneless](#detecção-de-mudanças-zoneless)
- [Boas Práticas de Template](#boas-práticas-de-template)
- [Otimização de Performance](#otimização-de-performance)
- [Checklist de Revisão](#checklist-de-revisão)

---

## Signals e Detecção de Mudanças

### Signal + OnPush dispara a detecção de mudanças automaticamente

```typescript
// Estado mutável + OnPush = a interface não atualiza
@Component({
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<p>{{ data.name }}</p>`,
})
export class UserProfile {
  data = { name: 'Alice' };
  changeName() { this.data.name = 'Bob'; } // a UI não vai atualizar!
}

// Signal + OnPush = detecção de mudanças automática
@Component({
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<p>{{ name() }}</p>`,
})
export class UserProfile {
  name = signal('Alice');
  changeName() { this.name.set('Bob'); } // dispara a detecção de mudanças automaticamente
}
```

### Mutação de objeto em @Input() não é detectada pelo OnPush

```typescript
// Mutar o objeto do Input — a referência não muda, OnPush não detecta
@Input() config!: Config;
updateConfig() { this.config.theme = 'dark'; }

// Criar uma nova referência
updateConfig() { this.config = { ...this.config, theme: 'dark' }; }
```

### computed() para estado derivado

```typescript
// effect usado para sincronizar estado — anti-padrão, pode disparar ciclos extras de detecção de mudanças
export class CartComponent {
  total = signal(0);
  discounted = signal(0);

  constructor() {
    effect(() => this.discounted.set(this.total() * 0.9));
  }
}

// computed para estado derivado — cálculo preguiçoso (lazy), sem efeitos colaterais
export class CartComponent {
  total = signal(0);
  discounted = computed(() => this.total() * 0.9);
}
```

### Leitura de Signal em effect() após await não é rastreada

```typescript
// Ler o Signal depois do await — a dependência não é rastreada
effect(async () => {
  const data = await fetchUserData();
  console.log(`Theme: ${theme()}`); // theme() não é rastreado!
});

// Ler de forma síncrona antes do await
effect(async () => {
  const currentTheme = theme(); // leitura síncrona, é rastreada
  const data = await fetchUserData();
  console.log(`Theme: ${currentTheme}`);
});
```

### effect só deve ser usado em cenários específicos

```typescript
// Usar effect para sincronizar dois Signals — sempre use computed
effect(() => { this.filtered.set(this.items().filter(i => i.active)); });

// Cenários legítimos para effect: manipulação de DOM, logs de analytics, assinatura de fontes externas
effect(() => {
  const canvas = this.canvasRef.nativeElement;
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = this.color();
  ctx.fillRect(0, 0, this.size(), this.size());
});

// "Não existem situações em que o effect é bom,
//    apenas situações em que ele é apropriado."
```

---

## Migração para Componentes Standalone

### No Angular 19+, standalone é o padrão

```typescript
// Componente legado baseado em NgModule
@Component({
  selector: 'old-component',
  standalone: false,
})
export class OldComponent {}

// Componente Standalone moderno (no Angular 19+, standalone é o padrão)
@Component({
  selector: 'user-profile',
  imports: [ProfilePhoto, RouterLink],
  template: `<profile-photo /><a routerLink="/edit">Edit</a>`,
})
export class UserProfile {}
```

### Sinais a observar na revisão

```typescript
// Sinais de que a migração é necessária:
// 1. standalone: false
// 2. declarations em @NgModule
// 3. Componentes importados via NgModule em vez de import direto

// Caminho de migração:
// 1. Remover standalone: false
// 2. Adicionar as dependências ao array imports do componente
// 3. Remover o NgModule se não restarem mais declarations
```

---

## Anti-padrões de RxJS

### subscribe() precisa estar acompanhado de takeUntilDestroyed

```typescript
// subscribe() nu — vazamento de memória! Continua recebendo dados após o componente ser destruído
@Component({ /* ... */ })
export class UserProfile implements OnInit {
  ngOnInit() {
    this.data$.subscribe(data => this.processData(data));
  }
}

// takeUntilDestroyed — cancela automaticamente quando o componente é destruído (precisa ser chamado no construtor ou em um contexto de injeção)
@Component({ /* ... */ })
export class UserProfile {
  constructor() {
    this.data$.pipe(takeUntilDestroyed()).subscribe(data => {
      this.processData(data);
    });
  }
}

// Uso fora do construtor — passando o DestroyRef
@Component({ /* ... */ })
export class UserProfile {
  private destroyRef = inject(DestroyRef);

  startListening() {
    this.data$.pipe(takeUntilDestroyed(this.destroyRef)).subscribe(/* ... */);
  }
}
```

### toSignal é preferível ao AsyncPipe

```typescript
// AsyncPipe — precisa de import, exige | async no template
@Component({
  imports: [AsyncPipe],
  template: `{{ data$ | async }}`,
})

// toSignal — cancela a assinatura automaticamente, pode ser usado em qualquer lugar
export class UserProfile {
  data = toSignal(this.data$, { initialValue: null });
  // o template usa data() diretamente
}
```

### Evite chamadas repetidas de toSignal

```typescript
// Cada chamada de toSignal cria uma nova assinatura
getData() {
  return toSignal(this.http.get('/api/data'));
}

// Armazene o resultado
data = toSignal(this.http.get('/api/data'), { initialValue: null });
```

---

## Detecção de Mudanças Zoneless

### Mutação de propriedade comum não é detectada (Angular 21+)

```typescript
// Em modo Zoneless, atribuição direta a propriedade comum não dispara detecção de mudanças
export class UserService {
  user: User | null = null;
  loadUser() { this.user = fetchResult; } // não dispara!
}

// Signal dispara a detecção de mudanças automaticamente
export class UserService {
  private _user = signal<User | null>(null);
  readonly user = this._user.asReadonly();
  loadUser() { this._user.set(fetchResult); }
}
```

### APIs do NgZone deixam de funcionar em Zoneless

```typescript
// NgZone.onStable nunca dispara em modo zoneless
ngZone.onStable.subscribe(() => { /* nunca dispara */ });

// Use afterNextRender
afterNextRender({ write: () => { /* executado após a detecção de mudanças */ } });
```

### Mutações em Reactive Forms exigem markForCheck

```typescript
// setValue/patchValue dos Reactive Forms não agendam detecção de mudanças automaticamente em zoneless
this.form.patchValue({ name: 'Alice' }); // a UI pode não atualizar

// Marque manualmente ou reflita via Signal
this.form.patchValue({ name: 'Alice' });
this.cdr.markForCheck();
```

### Disparadores válidos de detecção de mudanças em Zoneless

| Disparador | Descrição |
|--------|------|
| `signal.set()` / `.update()` | Atualização de Signal dispara automaticamente |
| `ChangeDetectorRef.markForCheck()` | Marcação manual |
| `ComponentRef.setInput()` | Binding de input |
| Callbacks de event listeners no template | Interação do usuário |

---

## Boas Práticas de Template

### Extraia lógica complexa para um Signal computed

```typescript
// Expressão complexa no template
template: `<div *ngIf="items.filter(i => i.active).length > 0 && user.role === 'admin'">`

// Extraída para computed
filteredItems = computed(() => this.items().filter(i => i.active));
shouldShow = computed(() => this.filteredItems().length > 0 && this.user().role === 'admin');
template: `@if (shouldShow()) { <div>...</div> }`
```

### Bindings nativos são preferíveis a NgClass / NgStyle

```typescript
// NgClass/NgStyle — overhead extra de diretivas
template: `<div [ngClass]="{active: isActive}" [ngStyle]="{'color': textColor}">`

// Bindings nativos de class/style — melhor performance
template: `<div [class.active]="isActive" [style.color]="textColor">`
```

### Membros exclusivos do template devem ser marcados como protected

```typescript
// Método exclusivo do template exposto como public
export class UserProfile {
  formatName(name: string) { return name.trim(); }
}

// Membros exclusivos do template devem usar protected
export class UserProfile {
  protected formatName(name: string) { return name.trim(); }
}
```

### Propriedades gerenciadas pelo Angular devem ser marcadas como readonly

```typescript
// input/output/model podem ser sobrescritos acidentalmente
userId = input<string>();
userSaved = output<void>();

// readonly evita atribuições acidentais
readonly userId = input<string>();
readonly userSaved = output<void>();
readonly userName = model<string>();
```

### Convenção de nomes: nome da ação, não do evento

```typescript
// Nomeado pelo evento
template: `<button (click)="handleClick()">Save</button>`

// Nomeado pela ação
template: `<button (click)="saveUserData()">Save</button>`
```

---

## Otimização de Performance

### effect é o último recurso — prefira computed

```typescript
// effect usado para sincronizar estado — dispara detecção de mudanças extra, pode causar loop infinito
effect(() => {
  this.filteredItems.set(this.items().filter(i => i.active));
});

// computed — cálculo preguiçoso (lazy), sem efeitos colaterais, sem detecção de mudanças extra
filteredItems = computed(() => this.items().filter(i => i.active));
```

### afterRenderEffect separa as fases de leitura e escrita

```typescript
// Sem fase especificada = mixedReadWrite = reflow extra de DOM
afterRenderEffect(() => {
  const height = el.offsetHeight; // leitura
  el.style.height = height + 10 + 'px'; // escrita
});

// Separar as fases reduz o reflow
afterRenderEffect({
  earlyRead: () => el.offsetHeight,
  write: (height) => { el.style.height = height() + 10 + 'px'; },
  read: () => verifyLayout(),
});
```

### inject() é preferível à injeção via construtor

```typescript
// Injeção via construtor — difícil de ler quando há muitas dependências
export class UserService {
  constructor(
    private http: HttpClient,
    private router: Router,
    private auth: AuthService,
  ) {}
}

// inject() — melhor inferência de tipos e legibilidade
export class UserService {
  private http = inject(HttpClient);
  private router = inject(Router);
  private auth = inject(AuthService);
}
```

---

## Checklist de Revisão

### Signals e Detecção de Mudanças

- [ ] Signal + OnPush usado para estado do template (não objeto mutável)
- [ ] Objetos de `@Input()` atualizados via nova referência (não mutação)
- [ ] Estado derivado usa `computed()`, não `effect()`
- [ ] Leitura de Signal em `effect()` ocorre antes do `await`
- [ ] `effect()` usado apenas para manipulação de DOM, logs, assinatura de fontes externas

### Componentes Standalone

- [ ] Sem `standalone: false` (Angular 19+)
- [ ] Componentes importam dependências via array `imports`
- [ ] Sem `@NgModule` desnecessário

### RxJS

- [ ] `.subscribe()` acompanhado de `takeUntilDestroyed` ou pipe `async`
- [ ] Preferência por `toSignal` em vez de `AsyncPipe`
- [ ] Sem chamadas repetidas de `toSignal`

### Zoneless

- [ ] Estado do template gerenciado via Signal (não propriedade comum)
- [ ] Sem `NgZone.onStable` / `NgZone.onMicrotaskEmpty`
- [ ] Mutações em Reactive Forms seguidas de `markForCheck()`

### Template

- [ ] Lógica complexa extraída para Signal `computed`
- [ ] Uso de `[class]`/`[style]` nativos em vez de `NgClass`/`NgStyle`
- [ ] Membros exclusivos do template marcados como `protected`
- [ ] Propriedades `input`/`output`/`model` marcadas como `readonly`
- [ ] Event handlers nomeados pela ação (`saveData` em vez de `handleClick`)

### Performance

- [ ] `effect()` não usado para sincronização de estado
- [ ] `afterRenderEffect` separa fases de leitura e escrita
- [ ] `inject()` usado para injeção de dependência
