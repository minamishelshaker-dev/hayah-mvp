import LoginForm from '@/components/LoginForm'

export default async function Page(props: { searchParams: Promise<{ next?: string }> }) {
  const { next } = await props.searchParams
  return <LoginForm next={next ?? ''} />
}
